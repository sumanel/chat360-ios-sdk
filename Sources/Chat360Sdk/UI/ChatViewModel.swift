import Foundation
import Combine
import Network

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var uiState = ChatUiState()
    /// Locally-cached conversation list, sourced from `ChatCacheRepository` - drives `ChatDrawer`'s
    /// history list. Refreshed on every cache write via `conversationsChanged`.
    @Published private(set) var conversations: [CachedConversation] = []
    /// From session-init's `bot_settings.bot_shortcuts` - renders as the header's shortcuts menu.
    @Published private(set) var shortcuts: [SessionShortcut] = []
    /// From session-init's `bot_settings.languages` - renders as the drawer's language chip row.
    @Published private(set) var languages: [SessionLanguage] = []

    private let repository: ChatRepository
    private let botId: String
    private let cache: ChatCacheRepository
    /// Raw (unrendered) text accumulated so far per streamId - chunk text arrives raw precisely
    /// so it can be concatenated as one string before RichTextParser ever sees it: a chunk
    /// boundary can land inside an HTML tag, and parsing each chunk individually would leave tag
    /// fragments as literal text. PlainTextContent re-parses this same accumulated string on
    /// every render, so no stripping happens here.
    private var streamRawText: [String: String] = [:]
    /// The conversation currently *displayed* - can diverge from `connectedConversationId` when
    /// the user is browsing an older cached conversation from the drawer (see `openConversation`).
    /// Published so `ChatDrawer` can highlight it in the conversation list.
    @Published private(set) var activeConversationId: String?
    /// The conversation the live `ChatRepository` socket is actually bound to - set once per
    /// `connect()`/`startNewSession()`, never by `openConversation()`. Chat360 has no "resume an
    /// arbitrary past room" endpoint, so this is always exactly one conversation: whichever one
    /// `startConnecting()`/`startNewChat()` most recently established. Live socket
    /// events/reconnects only ever belong to *this* conversation - caching and rendering both key
    /// off it, never off `activeConversationId`, so browsing an old conversation can never
    /// misattribute a live frame into it.
    private var connectedConversationId: String?
    private var activeRoomId: String?
    /// True while replaying cached/history messages through `handleEvent` - suppresses the
    /// re-caching that would otherwise happen (an already-cached message being re-appended is not
    /// a new message) and the echoed-user-message rendering that would otherwise double a message
    /// already shown optimistically at send time.
    private var restoringFromCache = false
    /// The REST history endpoint's `previous_cursor` from the last fetched page - `nil` once
    /// there's nothing older to fetch, matching `uiState.hasMoreHistory`.
    private var previousHistoryCursor: Int?
    private let cacheDecoder = JSONDecoder()
    private let cacheEncoder = JSONEncoder()
    private var cacheSubscription: AnyCancellable?
    private let pathMonitor = NWPathMonitor()

    init(baseUrl: String, botId: String, historyEnabled: Bool = true, conversationStarterEnabled: Bool = true) {
        self.repository = ChatRepository(baseUrl: baseUrl, botId: botId, historyEnabled: historyEnabled, conversationStarterEnabled: conversationStarterEnabled)
        self.botId = botId
        self.cache = .shared
        observeCache()
        observeConnectivity()
        startConnecting()
    }

    /// Test/DI seam.
    init(repository: ChatRepository, botId: String = "", cache: ChatCacheRepository = .shared) {
        self.repository = repository
        self.botId = botId
        self.cache = cache
        observeCache()
        observeConnectivity()
        startConnecting()
    }

    private func observeCache() {
        conversations = cache.conversations(botId: botId)
        cacheSubscription = cache.conversationsChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.conversations = self.cache.conversations(botId: self.botId)
            }
    }

    private func observeConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.uiState.isOffline = path.status != .satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.chat360.connectivity"))
    }

    private func startConnecting() {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.connect(
                onEvent: { [weak self] event in self?.handleEvent(event) },
                onConnected: { [weak self] in self?.uiState.isConnected = true; self?.uiState.error = nil },
                onError: { [weak self] error in
                    self?.uiState.isConnected = false
                    self?.uiState.error = (error as NSError).localizedDescription
                },
                onSlowConnectionChanged: { [weak self] slow in self?.uiState.isSlowConnection = slow },
                onMessageTimedOut: { [weak self] chatMsgId in self?.handleMessageTimedOut(chatMsgId) },
                onAppearanceLoaded: { [weak self] details, chatboxName in
                    guard let self else { return }
                    self.uiState.colorOverrides = details?.toColorOverrides()
                    self.uiState.logoOverride = details?.toLogoOverride()
                    self.uiState.botTitleOverride = chatboxName.flatMap { $0.isEmpty ? nil : $0 }
                    if let feedbackConfig = details?.feedback_config { self.uiState.feedbackConfig = feedbackConfig }
                },
                onOpenUrl: { [weak self] url in self?.uiState.pendingUrlToOpen = url },
                onSessionResumed: { [weak self] takeover, agent in
                    guard let self else { return }
                    self.uiState.isLiveChat = takeover
                    if let agent { self.uiState.assignedAgent = agent }
                },
                onFeedbackRequested: { [weak self] in self?.uiState.showFeedbackPrompt = true },
                onConversationStarted: { [weak self] roomId in
                    guard let self else { return false }
                    return await self.activateConversation(roomId)
                },
                onRawIncoming: { [weak self] raw in
                    guard let self, let conversationId = self.connectedConversationId else { return }
                    self.cache.cacheRaw(conversationId: conversationId, raw: raw)
                },
                onBotSettingsLoaded: { [weak self] shortcuts, languages in
                    self?.shortcuts = shortcuts
                    self?.languages = languages
                }
            )
        }
    }

    /// Cache hook invoked once the server's `room_id` is known - looks up/creates the matching
    /// local conversation, binds it, and replays cached messages if any exist. Returns `true` when
    /// it did (skipping the REST history/conversation-starter fetch that follows in
    /// `ChatRepository.establishSession()`).
    private func activateConversation(_ roomId: String) async -> Bool {
        activeRoomId = roomId
        let (conversationId, hasCachedMessages) = cache.activateForRoom(botId: botId, roomId: roomId, pendingId: connectedConversationId)
        connectedConversationId = conversationId
        activeConversationId = conversationId
        previousHistoryCursor = nil
        if hasCachedMessages {
            replayFromCache(conversationId: conversationId)
            return true
        }
        return await refreshConversationHistory(conversationId: conversationId, roomId: roomId)
    }

    private func replayFromCache(conversationId: String) {
        streamRawText.removeAll()
        uiState.messages = []
        uiState.hasMoreHistory = false
        restoringFromCache = true
        defer { restoringFromCache = false }
        for cached in cache.messages(conversationId: conversationId) {
            switch cached.kind {
            case .user:
                appendMessage(ChatMessage(chatMsgId: cached.chatMsgId, text: cached.payload, fromUser: true))
            case .raw:
                guard let data = cached.payload.data(using: .utf8),
                      let envelope = try? cacheDecoder.decode(RawSocketEnvelope.self, from: data) else { continue }
                handleEvent(envelope.toIncomingEvent())
            }
        }
        // Browsing a conversation other than the one the live socket is bound to is read-only -
        // there's no live room behind it to answer a quick-reply/form/etc. into (see
        // `openConversation`'s doc comment), so every row's reply affordances stay locked
        // regardless of whether the original live flow had already locked them.
        if conversationId != connectedConversationId {
            uiState.messages = uiState.messages.map { m in
                var m = m
                m.repliesEnabled = false
                return m
            }
        }
    }

    /// Network-seed path - only reached when the local cache has nothing yet for this
    /// conversation. Fetches the first (most recent) history page, replays it, then persists it as
    /// the conversation's RAW cache so future opens replay from cache instead.
    private func refreshConversationHistory(conversationId: String, roomId: String) async -> Bool {
        let response = await repository.fetchHistory(roomId: roomId)
        guard activeConversationId == conversationId else { return !response.history.isEmpty }
        streamRawText.removeAll()
        uiState.messages = []
        uiState.isArchived = false
        uiState.isLiveChat = false
        uiState.assignedAgent = nil
        restoringFromCache = true
        for item in response.history { handleEvent(item.toIncomingEvent()) }
        restoringFromCache = false
        let rawPayloads = response.history.compactMap { envelope -> String? in
            guard let data = try? cacheEncoder.encode(envelope) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        cache.replaceRawHistory(conversationId: conversationId, rawEnvelopes: rawPayloads)
        previousHistoryCursor = response.previous_cursor
        uiState.hasMoreHistory = response.previous_cursor != nil
        return !response.history.isEmpty
    }

    /// Scroll-to-top pagination - fetches one older page and prepends it in-memory only (not
    /// persisted to cache, matching Android's own deliberate simplification: the cache holds the
    /// most-recently-fetched page plus everything observed live since, and pages loaded this way
    /// are re-fetched from network again on the next cold reopen rather than staying cached).
    func loadMoreHistory() {
        guard uiState.hasMoreHistory, !uiState.isLoadingMoreHistory,
              let cursor = previousHistoryCursor, let roomId = activeRoomId else { return }
        uiState.isLoadingMoreHistory = true
        Task { [weak self] in
            guard let self else { return }
            let response = await self.repository.fetchMoreHistory(roomId: roomId, cursor: cursor)
            guard self.activeRoomId == roomId else { return }
            let older = response.history.compactMap { self.olderMessage(from: $0) }
            self.uiState.messages = older + self.uiState.messages
            self.previousHistoryCursor = response.previous_cursor
            self.uiState.hasMoreHistory = response.previous_cursor != nil
            self.uiState.isLoadingMoreHistory = false
        }
    }

    /// Converts one older history frame into a display message without handleEvent's live-state
    /// side effects (isLiveChat/assignedAgent/etc. reflect *current* status, not history).
    private func olderMessage(from envelope: RawSocketEnvelope) -> ChatMessage? {
        switch envelope.toIncomingEvent() {
        case .botMessage(let node):
            if node.text == nil, case .unsupported = node.content { return nil }
            if case .windowEvent = node.content { return nil }
            return ChatMessage(text: node.text ?? "", fromUser: false, content: node.content, repliesEnabled: false, author: node.author)
        case .echoedUserMessage(let chatMsgId, let text):
            guard let text, !text.isEmpty else { return nil }
            return ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true)
        case .inactivityNotice(let message, _):
            guard let message else { return nil }
            return ChatMessage(text: message, fromUser: false)
        default:
            return nil
        }
    }

    /// Header/drawer "New chat" - creates a fresh local conversation, points `activeConversationId`
    /// at it, then tears the socket down and re-runs session-init so the backend allocates a
    /// genuinely new room (mirrors the Android SDK's `ChatRepository.startNewSession()`).
    func startNewChat() {
        let newId = cache.createConversation(botId: botId)
        connectedConversationId = newId
        activeConversationId = newId
        activeRoomId = nil
        streamRawText.removeAll()
        uiState.messages = []
        uiState.hasMoreHistory = false
        uiState.isArchived = false
        uiState.isLiveChat = false
        uiState.assignedAgent = nil
        uiState.error = nil
        Task { [weak self] in
            await self?.repository.startNewSession()
        }
    }

    /// Sidebar tap on a past conversation - shows its cached transcript read-only. Chat360's
    /// backend has no "resume an arbitrary past room" endpoint (session-init always allocates a
    /// room; it doesn't accept one), so only the conversation created by the *current* live
    /// session can keep sending - opening an older one is browsing its history, not resuming it.
    func openConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else { return }
        activeConversationId = conversationId
        activeRoomId = conversations.first { $0.id == conversationId }?.roomId
        replayFromCache(conversationId: conversationId)
    }

    func renameConversation(_ conversationId: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cache.renameConversation(conversationId: conversationId, title: trimmed)
    }

    /// Deletes a cached conversation. Deleting the *connected* one always starts a fresh chat -
    /// its live room's cache row is gone, so nothing should keep writing into it. Deleting a
    /// merely-*displayed* (browsed) one falls back to another cached conversation, or a fresh
    /// chat if none remain (mirrors `ChatViewModel.deleteConversation` on Android).
    func deleteConversation(_ conversationId: String) {
        let wasConnected = conversationId == connectedConversationId
        let wasActive = conversationId == activeConversationId
        cache.deleteConversation(conversationId: conversationId)
        if wasConnected {
            startNewChat()
            return
        }
        guard wasActive else { return }
        if let fallback = conversations.first(where: { $0.id != conversationId }) {
            openConversation(fallback.id)
        } else {
            startNewChat()
        }
    }

    /// Header shortcuts-menu tap - sent as a real tracked user-authored message (mirrors Android's
    /// `sendShortcut`), so it also appears, caches, and gets ack-timeout coverage like any other reply.
    func selectShortcut(_ shortcut: SessionShortcut) {
        let chatMsgId = repository.sendShortcut(targetId: shortcut.targetId, label: shortcut.label)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: shortcut.label, fromUser: true))
    }

    /// Drawer language-chip tap - a flow restart: clears the transcript and every bit of
    /// live-session state before jumping to that language's entry node, mirroring Android's
    /// `switchLanguage` (which explicitly resets the same fields, since leaking e.g. a stale
    /// `isLiveChat`/`assignedAgent`/`showFeedbackPrompt` into the new language's flow would show
    /// stale live-chat/feedback UI on top of what's meant to be a fresh start). Also proactively
    /// reconnects first if the socket isn't currently connected - a silent jump into a dead socket
    /// would otherwise just do nothing.
    func switchLanguage(_ language: SessionLanguage) {
        if let connectedConversationId, activeConversationId != connectedConversationId {
            activeConversationId = connectedConversationId
        }
        streamRawText.removeAll()
        uiState.messages = []
        uiState.isAgentTyping = false
        uiState.isLiveChat = false
        uiState.assignedAgent = nil
        uiState.isArchived = false
        uiState.showFeedbackPrompt = false
        if !uiState.isConnected {
            repository.reconnectNow()
        }
        repository.jumpToNode(language.key)
    }

    /// Manual refresh/reconnect - bypasses the automatic reconnect backoff, reuses the current room.
    func reconnectNow() {
        repository.reconnectNow()
    }

    private func handleEvent(_ event: IncomingSocketEvent) {
        // A live frame arriving while the user is browsing a different (non-connected)
        // conversation from the drawer must not render into that unrelated transcript - it still
        // got cached correctly (`onRawIncoming` keys off `connectedConversationId`, not this), so
        // reopening the connected conversation will show it. Replay (cache or REST history) is
        // always allowed through: it only ever runs against whatever `activeConversationId` was
        // just set to immediately before it started.
        guard restoringFromCache || activeConversationId == connectedConversationId else { return }
        switch event {
        case .botMessage(let node):
            // An Unsupported node with no text at all renders nothing (yet) rather than an empty
            // bubble; one with fallback text still shows as plain text even before its specific
            // renderer exists. A WINDOW_EVENT node never renders a bubble at all - it only drives
            // the bridge.
            if node.text == nil, case .unsupported = node.content { return }
            if case .windowEvent = node.content { return }
            // isLiveChat flips true on the transfer notice OR any admin/operator-authored message,
            // and - unlike the source, which never resets it except via update_status - also
            // flips back false on the next bot-authored message. Deliberate simplification: it
            // makes replaying loaded history alone correctly reconstruct whether the session is
            // *currently* live, at the minor cost of diverging from source in the rare case a bot
            // message is ever injected mid-live-session.
            let isTransferNotice: Bool = { if case .agentTransferNotice = node.content { return true }; return false }()
            uiState.isLiveChat = isTransferNotice || node.author == .agent

            // A chatgpt_message streaming chunk concatenates onto the existing bubble sharing its
            // streamId instead of appending a new one; the flow stays paused (handled by the
            // always-open input bar already) until a chunk arrives with streamEnded=true.
            if node.streamId != nil {
                appendOrMergeStreamChunk(node)
                return
            }
            let needsPromptState: Bool = {
                switch node.content {
                case .emailPrompt, .phonePrompt, .datePrompt, .timePrompt: return true
                default: return false
                }
            }()
            let needsFormState: Bool = { if case .form = node.content { return true }; return false }()
            appendMessage(ChatMessage(
                text: node.text ?? "",
                fromUser: false,
                content: node.content,
                formState: needsFormState ? FormState() : nil,
                promptState: needsPromptState ? PromptState() : nil,
                author: node.author
            ))
        case .typingStatus(let isTyping):
            uiState.isAgentTyping = isTyping
        case .closeConnection:
            uiState.isConnected = false
        case .agentAssigned(let agent):
            uiState.assignedAgent = agent
        case .liveChatEnded:
            uiState.isLiveChat = false
        case .inactivityNotice(let message, let autoArchive):
            if let message { appendMessage(ChatMessage(text: message, fromUser: false)) }
            if autoArchive { uiState.isArchived = true }
        // A live echo of the user's own message only drives ChatRepository's ack-timeout
        // bookkeeping - the bubble already rendered optimistically when the user hit send.
        // Replaying cached/history content is the one case this needs to actually render:
        // there was no live optimistic append for it, so without this the user's own side of a
        // restored conversation would be silently missing.
        case .echoedUserMessage(let chatMsgId, let text):
            guard restoringFromCache, let text, !text.isEmpty else { return }
            appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
        // Ack/pong only drive ChatRepository's internal bookkeeping (ack-timeout cancellation,
        // heartbeat reset) - nothing further to reflect in the UI.
        default:
            break
        }
    }

    private func appendOrMergeStreamChunk(_ node: BotNode) {
        guard let streamId = node.streamId else { return }
        let mergedRaw = (streamRawText[streamId] ?? "") + (node.text ?? "")
        if node.streamEnded { streamRawText.removeValue(forKey: streamId) } else { streamRawText[streamId] = mergedRaw }

        if let index = uiState.messages.lastIndex(where: { $0.streamId == streamId }) {
            uiState.messages[index].text = mergedRaw
        } else {
            uiState.messages = uiState.messages.map { message in
                var m = message
                m.repliesEnabled = false
                return m
            }
            uiState.messages.append(ChatMessage(text: mergedRaw, fromUser: false, streamId: streamId))
        }
    }

    /// Clears the one-shot END-node URL after the UI has opened it.
    func clearPendingUrl() {
        uiState.pendingUrlToOpen = nil
    }

    /// Appending any message locks the quick replies of everything before it (widget behavior).
    /// A user-authored message also persists to the local cache, keyed by `connectedConversationId`
    /// (the room the live socket is actually bound to) - never by `activeConversationId`, which can
    /// point at a different, merely-browsed conversation with no live room behind it at all.
    /// Sending anything while browsing an old conversation snaps the display back to the connected
    /// one first, since there's nowhere coherent else for the message to land.
    private func appendMessage(_ message: ChatMessage) {
        if message.fromUser, !restoringFromCache, let connectedConversationId, activeConversationId != connectedConversationId {
            activeConversationId = connectedConversationId
            replayFromCache(conversationId: connectedConversationId)
        }
        uiState.messages = uiState.messages.map { m in
            var m = m
            m.repliesEnabled = false
            return m
        }
        uiState.messages.append(message)
        if message.fromUser, !restoringFromCache, let conversationId = connectedConversationId {
            cache.cacheUserMessage(conversationId: conversationId, text: message.text, chatMsgId: message.chatMsgId)
        }
    }

    func selectQuickReply(messageId: String, option: BotContent.MultiChoice.Option) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        if let index = uiState.messages.firstIndex(where: { $0.id == messageId }) {
            uiState.messages[index].repliesEnabled = false
            uiState.messages[index].selectedReplyIndex = option.index
        }
        let chatMsgId = repository.sendQuickReply(option)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: option.text, fromUser: true))
    }

    /// Answers a RATING node - disables the row and shows the value as the outgoing bubble.
    func selectRating(messageId: String, value: Int) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        if let index = uiState.messages.firstIndex(where: { $0.id == messageId }) {
            uiState.messages[index].repliesEnabled = false
            uiState.messages[index].selectedReplyIndex = value - 1
        }
        let chatMsgId = repository.sendRating(value)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: String(value), fromUser: true))
    }

    /// Answers the AUTOSUGGESTION sub-case of CUSTOMINPUT - single tap selects and submits.
    func selectAutoSuggestion(messageId: String, index: Int, text: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        if let msgIndex = uiState.messages.firstIndex(where: { $0.id == messageId }) {
            uiState.messages[msgIndex].repliesEnabled = false
            uiState.messages[msgIndex].selectedReplyIndex = index
        }
        let chatMsgId = repository.sendAutoSuggestion(text)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    func updatePromptValue(messageId: String, primary: String, secondary: String = "") {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        var current = uiState.messages[index].promptState ?? PromptState()
        guard !current.submitted else { return }
        current.value = primary
        current.secondaryValue = secondary
        uiState.messages[index].promptState = current
    }

    /// Answers an EMAIL node - blocked (no-op) unless the current draft passes InputValidators,
    /// same rules the composable uses to enable/disable Submit.
    func submitEmail(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), let prompt = message.promptState, !prompt.submitted else { return }
        let email = prompt.value.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !InputValidators.validateTest(email), InputValidators.validateEmail(email) else { return }
        markPromptSubmitted(messageId)
        let chatMsgId = repository.sendEmail(email)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: email, fromUser: true))
    }

    /// Answers a PHONE node. International + splitVariable sends two variables; otherwise a single combined value.
    func submitPhone(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .phonePrompt(let content) = message.content,
              let prompt = message.promptState, !prompt.submitted else { return }
        let countryCode = prompt.value.trimmingCharacters(in: .whitespaces)
        let nationalNumber = prompt.secondaryValue.trimmingCharacters(in: .whitespaces)
        let combined = countryCode + nationalNumber
        guard !countryCode.isEmpty, !nationalNumber.isEmpty, InputValidators.validatePhoneNumber(combined, international: true) else { return }
        markPromptSubmitted(messageId)
        let chatMsgId: String
        if content.splitVariable, let countryCodeVar = content.countryCodeVar {
            chatMsgId = repository.sendSplitPhone(countryCode: countryCode, nationalNumber: nationalNumber, countryCodeVar: countryCodeVar)
        } else {
            chatMsgId = repository.sendPhone(combined)
        }
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: combined, fromUser: true))
    }

    /// Answers a standalone DATE node - picking a date both fills and submits, single action.
    func selectDate(messageId: String, formattedDate: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }),
              case .datePrompt(let content) = uiState.messages[index].content,
              let prompt = uiState.messages[index].promptState, !prompt.submitted else { return }
        var updated = prompt
        updated.value = formattedDate
        updated.submitted = true
        uiState.messages[index].promptState = updated
        let chatMsgId = repository.sendDate(formattedDate: formattedDate, format: content.rules.dateFormat)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedDate, fromUser: true))
    }

    /// Answers a standalone TIME node.
    func submitTime(messageId: String, formattedTime: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), let prompt = message.promptState, !prompt.submitted else { return }
        markPromptSubmitted(messageId)
        let chatMsgId = repository.sendTime(formattedTime)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedTime, fromUser: true))
    }

    private func markPromptSubmitted(_ messageId: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        uiState.messages[index].promptState?.submitted = true
    }

    func toggleCheckbox(messageId: String, index: Int) {
        guard let msgIndex = uiState.messages.firstIndex(where: { $0.id == messageId }), uiState.messages[msgIndex].repliesEnabled else { return }
        if uiState.messages[msgIndex].checkedIndices.contains(index) {
            uiState.messages[msgIndex].checkedIndices.remove(index)
        } else {
            uiState.messages[msgIndex].checkedIndices.insert(index)
        }
    }

    func submitCheckboxes(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .multiOption(let content) = message.content,
              message.repliesEnabled, !message.checkedIndices.isEmpty else { return }
        let chatMsgId = repository.sendCheckboxOptions(allOptions: content.options, checkedIndices: message.checkedIndices)
        let text = content.options.filter { message.checkedIndices.contains($0.index) }.map(\.text).joined(separator: ", ")
        if let index = uiState.messages.firstIndex(where: { $0.id == messageId }) {
            uiState.messages[index].repliesEnabled = false
        }
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    /// Answers an IMAGE_BUTTON reply-type button; web_url buttons are opened externally by the UI, never reach here.
    func selectImageButton(messageId: String, card: BotContent.ImageButtons.Card, button: BotContent.ImageButtons.Button, submitType: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }), uiState.messages[index].repliesEnabled else { return }
        uiState.messages[index].repliesEnabled = false
        let chatMsgId = repository.sendImageButton(card: card, button: button, submitType: submitType)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: button.text, fromUser: true))
    }

    /// Answers a TEXT_CAROUSEL card/button/dynamic-pill tap; "link"-type taps are opened externally by the UI.
    func selectTextCarouselReply(messageId: String, text: String, clickedIndex: Int, targetId: String?) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }), uiState.messages[index].repliesEnabled else { return }
        uiState.messages[index].repliesEnabled = false
        let chatMsgId = repository.sendTextCarouselReply(text: text, clickedIndex: clickedIndex, targetId: targetId)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    /// Answers a WELCOME_SCREEN card tap.
    func selectWelcomeCard(messageId: String, card: BotContent.WelcomeScreen.Card, index cardIndex: Int) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }), uiState.messages[index].repliesEnabled else { return }
        uiState.messages[index].repliesEnabled = false
        let trimmedName = card.name?.trimmingCharacters(in: .whitespaces)
        let text = (trimmedName?.isEmpty == false ? trimmedName! : nil) ?? "Card \(cardIndex + 1)"
        let ctaTargetId = (card.ctaEnabled && card.ctaType == "component" && !(card.ctaLink?.isEmpty ?? true)) ? card.ctaLink : nil
        let chatMsgId = repository.sendWelcomeCard(cardTitle: text, clickedIndexOneBased: cardIndex + 1, ctaTargetId: ctaTargetId)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    /// IFRAME's postMessage bridge: the embedded page asked to advance the flow, no chat bubble involved.
    func advanceFromIframe(targetId: String) {
        repository.jumpToNode(targetId)
    }

    func updateFormField(messageId: String, fieldIndex: Int, value: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        var current = uiState.messages[index].formState ?? FormState()
        guard !current.submitted else { return }
        current.values[fieldIndex] = value
        uiState.messages[index].formState = current
    }

    /// Uploads a MEDIA field's picked file immediately (holding the URL as its draft value until the form submits).
    func uploadFormField(messageId: String, fieldIndex: Int, bytes: Data, fileName: String, mimeType: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        var current = uiState.messages[index].formState ?? FormState()
        current.uploadingFields.insert(fieldIndex)
        uiState.messages[index].formState = current

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.repository.uploadFormMedia(fileBytes: bytes, fileName: fileName, mimeType: mimeType, onProgress: { _ in })
                guard let idx = self.uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
                var state = self.uiState.messages[idx].formState ?? FormState()
                state.values[fieldIndex] = url
                state.fileNames[fieldIndex] = fileName
                state.uploadingFields.remove(fieldIndex)
                self.uiState.messages[idx].formState = state
            } catch {
                guard let idx = self.uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
                self.uiState.messages[idx].formState?.uploadingFields.remove(fieldIndex)
            }
        }
    }

    /// Validates every field with FormFieldValidator before sending - on failure, marks
    /// attemptedSubmit so FormContent starts showing each field's inline error, matching the
    /// widget's "errors appear once you try to submit" behavior.
    func submitForm(messageId: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }),
              case .form(let form) = uiState.messages[index].content else { return }
        var formState = uiState.messages[index].formState ?? FormState()
        guard !formState.submitted else { return }
        let hasErrors = form.fields.contains { FormFieldValidator.validate($0, value: formState.values[$0.index] ?? "") != nil }
        if hasErrors {
            formState.attemptedSubmit = true
            uiState.messages[index].formState = formState
            return
        }
        formState.submitted = true
        uiState.messages[index].formState = formState
        let chatMsgId = repository.sendFormResponse(values: formState.values, fields: form.fields, fileNames: formState.fileNames)
        let summary = form.fields.sorted { $0.index < $1.index }
            .map { formState.values[$0.index] ?? "" }
            .joined(separator: ", ")
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: summary.isEmpty ? "Form submitted" : summary, fromUser: true))
    }

    func sendFile(bytes: Data, fileName: String, mimeType: String) {
        let message = ChatMessage(text: "", fromUser: true, attachment: Attachment(fileName: fileName))
        appendMessage(message)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository.uploadAndSendFile(fileBytes: bytes, fileName: fileName, mimeType: mimeType) { [weak self] percent in
                    self?.updateAttachment(message.id) { $0.progress = percent }
                }
                self.updateAttachment(message.id) { $0.progress = 100; $0.uploaded = true }
            } catch {
                self.updateAttachment(message.id) { $0.failed = true }
            }
        }
    }

    /// A recording just stopped - hold it as a reviewable draft.
    func onVoiceRecordingCaptured(filePath: String, amplitudes: [Int], durationMs: Int64) {
        uiState.voiceDraft = VoiceDraftState(filePath: filePath, amplitudes: amplitudes, durationMs: durationMs)
    }

    /// Discards the draft file entirely - not recoverable.
    func cancelVoiceDraft() {
        let path = uiState.voiceDraft?.filePath
        uiState.voiceDraft = nil
        if let path { try? FileManager.default.removeItem(atPath: path) }
    }

    /// Uploads the draft then appends it as a sent bubble (retry just calls this again).
    func sendVoiceDraft() {
        guard let draft = uiState.voiceDraft, !draft.uploading else { return }
        uiState.voiceDraft?.uploading = true
        uiState.voiceDraft?.uploadProgress = 0
        uiState.voiceDraft?.error = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = URL(fileURLWithPath: draft.filePath)
                let data = try Data(contentsOf: url)
                let voiceUrl = try await self.repository.uploadAndSendVoiceMessage(
                    fileBytes: data, fileName: url.lastPathComponent, mimeType: "audio/mp4", transcript: ""
                ) { [weak self] percent in
                    self?.uiState.voiceDraft?.uploadProgress = percent
                }
                self.appendMessage(ChatMessage(
                    text: "",
                    fromUser: true,
                    voiceMessage: VoiceMessageInfo(localFilePath: draft.filePath, remoteUrl: voiceUrl, amplitudes: draft.amplitudes, durationMs: draft.durationMs)
                ))
                self.uiState.voiceDraft = nil
            } catch {
                self.uiState.voiceDraft?.uploading = false
                self.uiState.voiceDraft?.error = "Upload failed. Try again or cancel."
            }
        }
    }

    /// Submits the post-chat survey and ends the session.
    func submitFeedback(rating: Int?, feedbackText: String) {
        repository.sendConfigurableFeedback(rating: rating, feedbackText: feedbackText)
        uiState.showFeedbackPrompt = false
    }

    /// Skips the survey - the session was already held open only for it, so this just lets the screen close normally.
    func dismissFeedbackPrompt() {
        uiState.showFeedbackPrompt = false
    }

    private func updateAttachment(_ messageId: String, _ transform: (inout Attachment) -> Void) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }), var attachment = uiState.messages[index].attachment else { return }
        transform(&attachment)
        uiState.messages[index].attachment = attachment
    }

    private func handleMessageTimedOut(_ chatMsgId: String) {
        for index in uiState.messages.indices where uiState.messages[index].chatMsgId == chatMsgId {
            uiState.messages[index].failed = true
        }
    }

    func onInputChange(_ text: String) {
        uiState.inputText = text
    }

    func sendMessage() {
        let text = uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // The empty-message guard only applies outside live chat - live chat allows an empty submit through.
        guard !text.isEmpty || uiState.isLiveChat else { return }
        uiState.inputText = ""
        // No point handing this to the socket layer at all while offline - it would just sit
        // until the ack-timeout fires. Marking it failed immediately gives the user a retry
        // affordance right away instead of a multi-second stall.
        guard !uiState.isOffline else {
            appendMessage(ChatMessage(chatMsgId: UUID().uuidString, text: text, fromUser: true, failed: true))
            return
        }
        let chatMsgId = repository.sendFreeText(text)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    func disconnect() {
        repository.disconnect()
        pathMonitor.cancel()
    }

    /// Re-sends the user message that led to `messageId`'s AI response as a new outgoing message,
    /// removing the old AI bubble locally first. Not a distinct "regenerate" wire concept - the
    /// backend just sees a repeated user message; see design/Hyundai_v1_implementation_plan.md §3.4.
    func regenerate(messageId: String) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard let userMessage = uiState.messages[..<index].last(where: { $0.fromUser }) else { return }
        uiState.messages.remove(at: index)
        let chatMsgId = repository.sendFreeText(userMessage.text)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: userMessage.text, fromUser: true))
    }

    /// Toggles inline like/dislike on a bot message. Local UI state only for now - see
    /// design/Hyundai_v1_implementation_plan.md §3.4 for why this isn't sent anywhere yet.
    func setMessageFeedback(messageId: String, feedback: MessageFeedback) {
        guard let index = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        uiState.messages[index].feedback = uiState.messages[index].feedback == feedback ? nil : feedback
    }
}
