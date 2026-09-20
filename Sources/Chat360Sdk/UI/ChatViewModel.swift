import Foundation

@available(iOS 13.0, *)
@MainActor
public final class ChatViewModel: ObservableObject {
    private let repository: ChatRepository
    private let botId: String
    private let cache: ChatCacheRepository
    private let chatHistoryRepository: ChatHistoryRepository?
    private let suppressInitialBotMessages: Bool
    private let showPeriodicFeedbackPrompt: Bool
    private let periodicFeedbackPromptInterval: ClosedRange<Int>
    private let maintenanceApi: ThirdPartyTasksApiService?
    private let salesExecutiveGate: SalesExecutiveGate?

    @Published public private(set) var uiState = ChatUiState()
    @Published public private(set) var conversations: [CachedConversationEntity] = []
    @Published public private(set) var shortcuts: [String: String] = [:]
    @Published public private(set) var languages: [SessionLanguage] = []

    private var activeConversationId: String?
    // Bumped by every new room-switch/history-load attempt (opening a conversation, connecting,
    // starting or re-showing a new chat, snapping back to the connected room to send). A load
    // captures the value it started under and re-checks it after every `await` (a cache read, a
    // history fetch) before touching `uiState` or the shared vars below: if a newer attempt began
    // meanwhile it bails instead of clobbering what that one already wrote. The old
    // `activeConversationId == conversationId` check isn't enough - an A -> B -> A switch makes it
    // true again for a stale first visit to A, and two overlapping replays each cleared the
    // transcript then both appended, mixing two conversations into one. Everything here runs on the
    // main actor, so the suspension points are the only place a load can be overtaken.
    private var loadGeneration = 0
    /// How long a send from an unresumable old room waits for its fresh session to connect.
    static var newSessionSendTimeout: TimeInterval = 20
    private func beginLoad() -> Int {
        loadGeneration += 1
        return loadGeneration
    }
    private func isCurrentLoad(_ generation: Int) -> Bool { generation == loadGeneration }
    private var connectedConversationId: String?
    private var connectedRoomId: String?
    private var conversationPersisted = false
    private var pendingRawEnvelopes: [String] = []
    // A room the server already created for this user that has never received a user message
    // (see `conversationPersisted`) and that the socket has since moved away from - stashed so
    // "New chat" can go back to it instead of asking the server for yet another room, which used
    // to leave one empty ghost room behind per tap. `envelopes` is its buffered opener
    // (`pendingRawEnvelopes` at the time it was left). Cleared once the user sends anything in it.
    private struct BlankRoom {
        let conversationId: String
        let roomId: String
        let envelopes: [String]
    }
    private var blankRoom: BlankRoom?
    private var restoringFromCache = false
    // The timestamp of the earliest real user message in whatever batch is about to be replayed/
    // refreshed/backfilled, set once up front - nil if there isn't one. See the comment at its
    // read site in `handleEvent` for why suppression has to be judged by *when* a bot message
    // happened relative to this, not by whether a user message exists anywhere in the batch.
    private var cachedEarliestUserTimestampMs: Int64?
    // The node id already recorded (see `ChatCacheRepository.suppressedOpenerNodeId`) as this
    // conversation's one suppressible opening greeting, loaded once up front for whatever batch
    // is about to be replayed/refreshed/backfilled - nil if this conversation hasn't had its
    // opener identified yet (falls back to the timestamp heuristic below, just for that one load).
    private var cachedSuppressedOpenerNodeId: String?
    private var pendingSnapBackChatMsgId: String?
    private var previousHistoryCursor: Int?
    private var streamRawText: [String: String] = [:]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var conversationsObservationTask: Task<Void, Never>?
    // Keyed per conversation, not just "the current one" - an absolute deadline, not a paused
    // duration, so it keeps counting down in real time whether or not that conversation is the
    // one currently being viewed. Switching away and back should resume showing whatever's
    // actually left, not restart, and only actual expiry (not merely having left and returned)
    // should trigger a fresh hour on the next message.
    private var sessionTimerExpiresAtByConversation: [String: Date] = [:]
    // The server's own record of when this room's session actually started, keyed by
    // conversation - anchors the countdown to real session age instead of "whenever this device
    // happened to send its first message in it", which could understate a resumed room's true
    // elapsed time. Populated by `handleSessionTimeReceived`, consumed by
    // `ensureSessionTimerStarted`; a conversation with no entry here just falls back to the old
    // client-side guess (e.g. the request hasn't answered yet, or this bot doesn't support it).
    private var serverSessionCreatedAtByConversation: [String: Date] = [:]
    // Periodic "how's it going" feedback prompt - fires every random N live bot replies (N drawn
    // from `periodicFeedbackPromptInterval`), scoped per conversation. Was originally a single
    // pair of counters shared across every conversation
    // in the ViewModel's lifetime, which meant switching to (or starting) a different conversation
    // silently carried over progress from whatever you were doing before - e.g. 2 replies in room
    // A plus 1 in a brand new room B would fire on room B's very first reply.
    private var botRepliesSinceLastFeedbackPromptByConversation: [String: Int] = [:]
    private var nextFeedbackPromptThresholdByConversation: [String: Int] = [:]

    public init(
        repository: ChatRepository,
        botId: String,
        cache: ChatCacheRepository,
        chatHistoryRepository: ChatHistoryRepository? = nil,
        suppressInitialBotMessages: Bool = false,
        showPeriodicFeedbackPrompt: Bool = true,
        periodicFeedbackPromptInterval: ClosedRange<Int> = 8...12,
        maintenanceApi: ThirdPartyTasksApiService? = nil,
        welcomeTextRepository: WelcomeTextRepository? = nil,
        salesExecutiveGate: SalesExecutiveGate? = nil,
        initialAssistantModeIndex: Int = 0
    ) {
        self.assistantModeIndex = initialAssistantModeIndex
        self.repository = repository
        self.botId = botId
        self.cache = cache
        self.chatHistoryRepository = chatHistoryRepository
        self.roomRoles = chatHistoryRepository?.roomRoles ?? [:]
        self.suppressInitialBotMessages = suppressInitialBotMessages
        self.showPeriodicFeedbackPrompt = showPeriodicFeedbackPrompt
        self.periodicFeedbackPromptInterval = periodicFeedbackPromptInterval
        self.maintenanceApi = maintenanceApi
        self.salesExecutiveGate = salesExecutiveGate
        if let history = chatHistoryRepository {
            // A room created on this device is badged with the role it was made with, before the server lists it.
            repository.onFreshSession = { [weak self] roomId, variables in
                history.rememberLocalRole(roomId: roomId, role: variables[Chat360FeatureConfig.assistantRoleKey])
                Task { @MainActor in self?.roomRoles = history.roomRoles }
            }
        }

        loadWelcomeText(welcomeTextRepository)

        conversationsObservationTask = Task { [weak self] in
            guard let self else { return }
            for await list in self.cache.conversations(botId: botId) {
                self.conversations = list
            }
        }

        refreshRoomsList()

        Task { [weak self] in
            guard let self else { return }
            if self.applyAccess(await self.checkAccess()) {
                self.neverConnected = true
                return
            }
            await self.connectFirstTime()
        }
    }

    // Re-fetches the server room list into the cache; also run each time the history menu opens and
    // from its retry notice. No-ops when history isn't configured.
    /// roomId -> `agent_role` for the history list's role badges; empty when history isn't configured.
    @Published public private(set) var roomRoles: [String: String] = [:]

    func refreshRoomsList() {
        guard let chatHistoryRepository else { return }
        Task { [weak self] in
            guard let self else { return }
            // Don't assign the fetched list to `conversations` directly - `refreshRooms()`
            // already reconciles it into the local cache (see `syncAgentRooms`), which
            // `conversationsObservationTask` picks up via its live subscription. Writing it
            // here too raced that subscription: this one-shot assignment could land after
            // the stream's already-correct snapshot and stomp it with a narrower one, then
            // never get corrected until some unrelated local write re-fired the stream.
            let refreshed = await chatHistoryRepository.refreshRooms()
            self.roomRoles = chatHistoryRepository.roomRoles
            self.update {
                $0.isHistoryUnavailable = refreshed == nil
                if refreshed != nil { $0.hasMoreRooms = chatHistoryRepository.hasMoreRooms }
            }
        }
    }

    // Loads the next page of older rooms into the history list ("Load more").
    func loadMoreRooms() {
        guard let chatHistoryRepository, !uiState.isLoadingMoreRooms else { return }
        update { $0.isLoadingMoreRooms = true }
        Task { [weak self] in
            guard let self else { return }
            let ok = await chatHistoryRepository.loadMoreRooms()
            self.roomRoles = chatHistoryRepository.roomRoles
            self.update {
                $0.isLoadingMoreRooms = false
                $0.hasMoreRooms = chatHistoryRepository.hasMoreRooms
                if ok { $0.isHistoryUnavailable = false }
            }
        }
    }

    private func update(_ transform: (inout ChatUiState) -> Void) {
        transform(&uiState)
    }

    // Unsent input text per conversation id - see `setActiveConversationId`.
    private var drafts: [String: String] = [:]

    private func setActiveConversationId(_ id: String?) {
        let previous = activeConversationId
        // Unsent text belongs to the room it was typed in: parked under that room when leaving it
        // and restored on return, instead of the one shared input box carrying it into whichever
        // room is opened next. The very first activation (no previous room yet) is left alone so
        // text typed while the first connection was still coming up isn't wiped.
        let switching = previous != nil && previous != id
        if switching, let previous { drafts[previous] = uiState.inputText }
        activeConversationId = id
        // Restores whatever's already running for this specific conversation (if anything) -
        // switching to a conversation with time left resumes that countdown rather than hiding
        // or restarting it; one with no entry yet (or a past deadline) shows nothing until a
        // message is actually sent in it. If nothing's running in memory yet (e.g. right after a
        // cold launch), `refreshSessionTimerFromPersisted` below checks disk for the same thing.
        let expiresAt = id.flatMap { sessionTimerExpiresAtByConversation[$0] }
        let restoredDraft = switching ? (id.flatMap { drafts[$0] } ?? "") : nil
        update {
            $0.activeConversationId = id
            $0.sessionTimerExpiresAt = expiresAt
            if let restoredDraft { $0.inputText = restoredDraft }
        }
        Task { [weak self] in
            await self?.refreshPendingFeedback(conversationId: id)
            await self?.refreshMessageReactions(conversationId: id)
            if let id { await self?.refreshSessionTimerFromPersisted(conversationId: id) }
        }
    }

    // Shows the countdown the instant a conversation with real time left is opened, even before
    // any live reconnect to it happens - without this, a restarted app has nothing in memory for
    // any conversation until it reconnects, so the timer would stay hidden until a new message
    // was sent, rather than reflecting time that's already genuinely still on the clock.
    private func refreshSessionTimerFromPersisted(conversationId: String) async {
        guard sessionTimerExpiresAtByConversation[conversationId] == nil else { return }
        guard let createdAtMs = await cache.sessionCreatedAt(conversationId: conversationId) else { return }
        // Only for a conversation that's actually had a real message - a brand-new chat's session
        // can exist server-side before the user has said anything, and the timer shouldn't appear
        // until they've actually started the conversation.
        guard await cache.messages(conversationId: conversationId).contains(where: { $0.kind == "USER" }) else { return }
        let createdAt = Date(timeIntervalSince1970: Double(createdAtMs) / 1000)
        let expiresAt = createdAt.addingTimeInterval(3600)
        guard expiresAt > Date() else { return }
        serverSessionCreatedAtByConversation[conversationId] = createdAt
        sessionTimerExpiresAtByConversation[conversationId] = expiresAt
        guard activeConversationId == conversationId else { return }
        update { $0.sessionTimerExpiresAt = expiresAt }
    }

    // Dislike must durably block the chat with a mandatory feedback prompt - including across
    // app restarts, conversation switches, and reopening the same room later - with no backend
    // to ask "is feedback still owed here". The local cache (already used for message/history
    // persistence) is the only thing that survives all of those, so a pending row there is the
    // source of truth this reads back from, rather than any in-memory flag. The timestampMs
    // carried alongside it is what lets cancelling also undo the reaction on the right message
    // even after a restart, when the messageId that was disliked no longer matches anything
    // on screen.
    private func refreshPendingFeedback(conversationId: String?) async {
        guard let conversationId else {
            update { $0.pendingFeedbackMessageId = nil; $0.pendingFeedbackTimestampMs = nil }
            return
        }
        let pending = await cache.pendingFeedbackEntries(conversationId: conversationId)
        guard activeConversationId == conversationId else { return }
        update {
            $0.pendingFeedbackMessageId = pending.first?.messageId
            $0.pendingFeedbackTimestampMs = pending.first?.timestampMs
        }
    }

    // Keyed on `timestampMs`, not `ChatMessage.id` - the id is a fresh random UUID minted every
    // time a message is constructed, including on replay, so it can't identify "the same
    // message" across an app restart. The server timestamp is the only thing that round-trips
    // identically through both live delivery and replay.
    private func refreshMessageReactions(conversationId: String?) async {
        guard let conversationId else {
            update { $0.messageReactions = [:] }
            return
        }
        let reactions = await cache.messageReactions(conversationId: conversationId)
        guard activeConversationId == conversationId else { return }
        update { $0.messageReactions = reactions }
    }

    private func setReaction(timestampMs: Int64?, liked: Bool) {
        guard let timestampMs, let conversationId = activeConversationId else { return }
        update { $0.messageReactions[timestampMs] = liked }
        Task { [weak self] in
            guard let self else { return }
            await self.cache.setMessageReaction(conversationId: conversationId, timestampMs: timestampMs, liked: liked)
        }
    }

    public func likeMessage(timestampMs: Int64?) {
        setReaction(timestampMs: timestampMs, liked: true)
        reportFeedback(timestampMs: timestampMs, feedback: "Like", remarks: nil)
    }

    public func dislikeMessage(messageId: String, timestampMs: Int64?) {
        guard let conversationId = activeConversationId else { return }
        setReaction(timestampMs: timestampMs, liked: false)
        Task { [weak self] in
            guard let self else { return }
            await self.cache.markFeedbackPending(messageId: messageId, conversationId: conversationId, timestampMs: timestampMs)
            await self.refreshPendingFeedback(conversationId: conversationId)
        }
    }

    public func submitDislikeFeedback(messageId: String, text: String) {
        let timestampMs = uiState.pendingFeedbackTimestampMs
        // Deliberately NOT sending a socket `nodeType:"feedback"` frame here. That frame is
        // wire-identical to the end-of-conversation feedback submission, so the backend treats
        // a per-message dislike as "conversation done" and stops driving the flow for the room -
        // every message the user sends afterward then goes unanswered. The dislike is still
        // recorded out-of-band via reportFeedback() below (third-party-tasks analytics API).
        reportFeedback(timestampMs: timestampMs, feedback: "Dislike", remarks: text)
        Task { [weak self] in
            guard let self else { return }
            await self.cache.clearPendingFeedback(messageId: messageId)
            await self.refreshPendingFeedback(conversationId: self.activeConversationId)
        }
    }

    // Reports a like/dislike to the third-party-tasks feedback API - a separate, analytics-side
    // record from the bot's own conversational feedback message sent over the socket. Silently
    // no-ops if third-party-tasks isn't configured (no clientId/apiKey/endUserId) or the message
    // being reacted to can't be found, e.g. after a restart if the conversation hasn't replayed
    // yet - matches the existing best-effort pattern used for rooms/list, room/update, etc.
    private func reportFeedback(timestampMs: Int64?, feedback: String, remarks: String?) {
        guard let chatHistoryRepository else {
            NSLog("[Chat360] Skipping %@ feedback report: third-party-tasks not configured", feedback)
            return
        }
        guard let timestampMs, let conversationId = activeConversationId,
              let roomId = conversations.first(where: { $0.id == conversationId })?.roomId
        else {
            NSLog("[Chat360] Skipping %@ feedback report: no active conversation/room", feedback)
            return
        }
        guard let sessionId = repository.currentSessionId() else {
            NSLog("[Chat360] Skipping %@ feedback report: no session id yet", feedback)
            return
        }
        guard let index = uiState.messages.firstIndex(where: { $0.timestampMs == timestampMs }),
              let nodeId = uiState.messages[index].nodeId
        else {
            NSLog("[Chat360] Skipping %@ feedback report: message not found (timestampMs=%lld)", feedback, timestampMs)
            return
        }
        let response = uiState.messages[index].text
        let query = uiState.messages[..<index].last(where: { $0.fromUser })?.text ?? ""
        Task {
            await chatHistoryRepository.submitFeedback(
                roomId: roomId, sessionId: sessionId, messageId: nodeId, query: query, response: response,
                feedback: feedback, remarks: remarks
            )
        }
    }

    // The X on the feedback dialog undoes the dislike itself, not just the mandatory-feedback
    // obligation - dislike-then-skip-feedback must stay impossible, so this can't be a bare
    // dismiss. It reverts the reaction (using the timestampMs captured alongside the pending
    // row, since the messageId alone can't be trusted to still match a message after a restart)
    // so the thumbs-down un-highlights and the message goes back to unreacted.
    public func cancelDislikeFeedback(messageId: String) {
        let timestampMs = uiState.pendingFeedbackTimestampMs
        let conversationId = activeConversationId
        Task { [weak self] in
            guard let self else { return }
            await self.cache.clearPendingFeedback(messageId: messageId)
            if let timestampMs, let conversationId {
                await self.cache.clearMessageReaction(conversationId: conversationId, timestampMs: timestampMs)
                self.update { $0.messageReactions[timestampMs] = nil }
            }
            await self.refreshPendingFeedback(conversationId: self.activeConversationId)
        }
    }

    private func handleEvent(_ event: IncomingSocketEvent) {
        if !restoringFromCache && activeConversationId != connectedConversationId {
            NSLog("[Chat360] handleEvent dropped (viewing a different conversation than the one connected): active=%@ connected=%@", activeConversationId ?? "nil", connectedConversationId ?? "nil")
            return
        }
        switch event {
        case .botMessage(let node):
            // Guards against seeing the same reply twice - e.g. `backfillMissingReplies` recovers
            // it via a direct history fetch, and moments later the live socket (which opens after
            // that fetch completes) redelivers the same node once connected. Node id alone isn't
            // enough to identify "the same message" though - flow builders commonly reuse one
            // node id for a generic prompt (e.g. a MULTI_CHOICE follow-up) that gets revisited
            // with different generated content each time, so two genuinely different replies can
            // legitimately share a node id. Requiring the timestamp to match too is what actually
            // distinguishes a true redelivery (identical payload, identical timestamp) from a
            // fresh visit to the same flow node (same id, new timestamp).
            if let nodeId = node.nodeId, let ts = node.timestampMs,
               uiState.messages.contains(where: { $0.nodeId == nodeId && $0.timestampMs == ts }) {
                NSLog("[Chat360] botMessage dropped as duplicate: nodeId=%@ ts=%lld", nodeId, ts)
                return
            }
            update { $0.isAgentTyping = false }
            // Hides the bot's opening/greeting node permanently, not just before the first live
            // send - it's always present in the underlying flow (and gets replayed from cache
            // when reopening a past conversation). Identified by remembered node id, not by
            // comparing timestamps: a live send is the one moment this is unambiguous (true
            // chronological order, no clock skew or cache-write-race possible), so the first time
            // a conversation identifies its opener live, that decision is persisted and reused on
            // every future replay - re-deriving it from timestamps each time can't reliably tell
            // the real opener apart from a genuine reply that happens to land close in time to it.
            if suppressInitialBotMessages {
                let isSuppressibleOpener: Bool
                if restoringFromCache {
                    if let openerNodeId = cachedSuppressedOpenerNodeId {
                        // Some flows answer every question through the opener's own node, so the node id
                        // alone would hide every reply on replay. It only marks an opener until the user
                        // has said something: judged by the transcript rebuilt so far (replay is
                        // chronological) or, when the window starts mid-chat, by the earliest user timestamp.
                        let userAlreadySpoke = uiState.messages.contains(where: { $0.fromUser })
                            || (cachedEarliestUserTimestampMs.map { earliest in node.timestampMs.map { $0 >= earliest } ?? true } ?? false)
                        isSuppressibleOpener = node.nodeId != nil && node.nodeId == openerNodeId && !userAlreadySpoke
                    } else {
                        // This conversation has never had its opener identified live (e.g.
                        // synced-in history) - fall back to the timestamp heuristic just for this
                        // one load, then remember whatever it decides so it's stable from here on.
                        let hasUserMessage: Bool
                        if let earliest = cachedEarliestUserTimestampMs {
                            hasUserMessage = node.timestampMs.map { $0 >= earliest - Self.replyClockSkewToleranceMs } ?? true
                        } else {
                            hasUserMessage = false
                        }
                        isSuppressibleOpener = !hasUserMessage
                        if isSuppressibleOpener, let nodeId = node.nodeId, let conversationId = activeConversationId {
                            cachedSuppressedOpenerNodeId = nodeId
                            let cache = self.cache
                            Task { await cache.setSuppressedOpenerNodeIdIfMissing(conversationId: conversationId, nodeId: nodeId) }
                        }
                    }
                } else {
                    isSuppressibleOpener = !uiState.messages.contains(where: { $0.fromUser })
                    if isSuppressibleOpener, let nodeId = node.nodeId, let conversationId = connectedConversationId {
                        let cache = self.cache
                        Task { await cache.setSuppressedOpenerNodeIdIfMissing(conversationId: conversationId, nodeId: nodeId) }
                    }
                }
                if isSuppressibleOpener {
                    NSLog("[Chat360] botMessage dropped as suppressed opener: nodeId=%@ restoringFromCache=%@", node.nodeId ?? "nil", String(restoringFromCache))
                    return
                }
            }
            if node.text == nil, case .unsupported = node.content {
                NSLog("[Chat360] botMessage dropped as unsupported/empty: nodeId=%@", node.nodeId ?? "nil")
                return
            }
            if case .windowEvent = node.content {
                NSLog("[Chat360] botMessage dropped as windowEvent: nodeId=%@", node.nodeId ?? "nil")
                return
            }
            update {
                $0.isAgentTyping = false
                if case .agentTransferNotice = node.content {
                    $0.isLiveChat = true
                } else if node.author == .agent {
                    $0.isLiveChat = true
                } else {
                    $0.isLiveChat = false
                }
            }
            // Counts once per logical reply, not once per event - a streamed reply fires this
            // whole case repeatedly (once per chunk, same streamId), so only its first chunk
            // (before `streamRawText` has an entry for it) counts as "one more bot reply".
            let isNewStreamMessage = node.streamId.map { streamRawText[$0] == nil } ?? true
            if !restoringFromCache && isNewStreamMessage {
                registerLiveBotReplyForFeedbackPrompt()
                // Shown once the bot has actually answered, not the instant the user's own
                // message goes out - `ensureSessionTimerStarted`'s own "already running or not
                // yet expired" guard means this is still a no-op on every reply after the first.
                ensureSessionTimerStarted()
            } else {
                NSLog(
                    "[Chat360] Skipping feedback-prompt count: restoringFromCache=%@ isNewStreamMessage=%@ nodeId=%@",
                    String(restoringFromCache), String(isNewStreamMessage), node.nodeId ?? "nil"
                )
            }
            if node.streamId != nil {
                appendOrMergeStreamChunk(node)
                return
            }
            var formState: FormState? = nil
            if case .form = node.content { formState = FormState() }
            var promptState: PromptState? = nil
            switch node.content {
            case .emailPrompt, .phonePrompt, .datePrompt, .timePrompt: promptState = PromptState()
            default: break
            }
            appendMessage(ChatMessage(
                text: node.text ?? "",
                fromUser: false,
                timeText: formatMessageTime(node.timestampMs),
                content: node.content,
                formState: formState,
                promptState: promptState,
                author: node.author,
                timestampMs: node.timestampMs,
                nodeId: node.nodeId
            ), cacheUserMessage: false)
        case .typingStatus(let isTyping):
            update { $0.isAgentTyping = isTyping }
        case .closeConnection:
            update { $0.isConnected = false }
        case .agentAssigned(let agent):
            update { $0.assignedAgent = agent }
        case .liveChatEnded:
            update { $0.isLiveChat = false }
        case .inactivityNotice(let message, let autoArchive):
            if let message { appendMessage(ChatMessage(text: message, fromUser: false), cacheUserMessage: false) }
            if autoArchive { update { $0.isArchived = true } }
        case .echoedUserMessage(let chatMsgId, let text, let timestampMs):
            if restoringFromCache && chatMsgId != pendingSnapBackChatMsgId {
                if let text {
                    appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true, timeText: formatMessageTime(timestampMs)), cacheUserMessage: false)
                }
            }
        default:
            break
        }
    }

    private func appendOrMergeStreamChunk(_ node: BotNode) {
        guard let streamId = node.streamId else { return }
        let mergedRaw = (streamRawText[streamId] ?? "") + (node.text ?? "")
        if node.streamEnded { streamRawText.removeValue(forKey: streamId) } else { streamRawText[streamId] = mergedRaw }
        update { state in
            if let index = state.messages.lastIndex(where: { $0.streamId == streamId }) {
                state.messages[index].text = mergedRaw
            } else {
                state.messages = state.messages.map { message in
                    var updated = message
                    updated.repliesEnabled = false
                    return updated
                }
                state.messages.append(ChatMessage(text: mergedRaw, fromUser: false, streamId: streamId, timestampMs: node.timestampMs, nodeId: node.nodeId))
            }
        }
    }

    public func clearPendingUrl() {
        update { $0.pendingUrlToOpen = nil }
    }

    private func appendMessage(_ message: ChatMessage, cacheUserMessage: Bool? = nil) {
        let shouldCache = cacheUserMessage ?? message.fromUser
        let target = connectedConversationId
        if message.fromUser, !restoringFromCache, let target, activeConversationId != target {
            setActiveConversationId(target)
            pendingSnapBackChatMsgId = message.chatMsgId
            let generation = beginLoad()
            Task { [weak self] in
                guard let self else { return }
                await self.restoreConversation(conversationId: target, roomId: self.connectedRoomId, generation: generation)
                self.pendingSnapBackChatMsgId = nil
                self.appendMessageNow(message, cacheUserMessage: shouldCache)
            }
            return
        }
        appendMessageNow(message, cacheUserMessage: shouldCache)
    }

    private func appendMessageNow(_ message: ChatMessage, cacheUserMessage: Bool) {
        update { state in
            state.messages = state.messages.map { m in
                var updated = m
                updated.repliesEnabled = false
                return updated
            }
            state.messages.append(message)
        }
        if cacheUserMessage, let conversationId = connectedConversationId {
            let roomId = connectedRoomId
            Task { [weak self] in
                guard let self else { return }
                await self.ensureConversationPersisted(conversationId: conversationId, roomId: roomId)
                await self.cache.cacheUserMessage(conversationId: conversationId, text: message.text, chatMsgId: message.chatMsgId, botId: self.botId)
                // Marks this conversation as owed a reply until a bot message is actually seen
                // for it again (live or via a forced re-fetch) - see `ReplyPendingEntity`. Covers
                // every send path uniformly (typed text, nudges, regenerate, form submits, etc.)
                // since they all funnel through here.
                await self.cache.markReplyPending(conversationId: conversationId, chatMsgId: message.chatMsgId)
                self.upsertLiveConversationEntry(conversationId: conversationId, roomId: roomId, title: message.text)
            }
        }
    }

    // Only (re)starts when nothing is currently running for THIS conversation, or its last
    // deadline already passed - a message sent while its hour is still counting down leaves it
    // alone, and merely having left and come back doesn't count as expiry.
    private func ensureSessionTimerStarted() {
        guard let conversationId = activeConversationId else { return }
        let now = Date()
        if let expiresAt = sessionTimerExpiresAtByConversation[conversationId], expiresAt > now { return }
        // Anchor to the server's real session creation time when we have it, rather than "now" -
        // a resumed room's session may have actually started well before this device sent
        // anything in it, and the client-side guess would understate how much time is really left.
        let anchor = serverSessionCreatedAtByConversation[conversationId] ?? now
        let newExpiresAt = anchor.addingTimeInterval(3600)
        sessionTimerExpiresAtByConversation[conversationId] = newExpiresAt
        update { $0.sessionTimerExpiresAt = newExpiresAt }
    }

    // `connectedConversationId` is the room whose session this response actually belongs to -
    // the request is sent on every socket connect, keyed to the room being connected at that
    // moment (see `ChatRepository.openSocket()`), so that's the correct key here too even if the
    // user has since navigated to a different conversation before the response comes back.
    private func handleSessionTimeReceived(_ createdAt: Date) {
        guard let conversationId = connectedConversationId else { return }
        serverSessionCreatedAtByConversation[conversationId] = createdAt
        // Saved to disk too, so a future cold launch can show the countdown for this conversation
        // the instant it's opened, without needing a live reconnect to re-derive it first - see
        // `refreshSessionTimerFromPersisted`.
        let createdAtMs = Int64(createdAt.timeIntervalSince1970 * 1000)
        let cache = self.cache
        Task { await cache.setSessionCreatedAt(conversationId: conversationId, createdAtMs: createdAtMs) }
        // The timer may have already started using "now" as a rough stand-in, if the user sent
        // their first message before this response made it back - correct it now that the real
        // anchor is known, rather than leaving it on the earlier guess for the rest of the hour.
        guard sessionTimerExpiresAtByConversation[conversationId] != nil else { return }
        let correctedExpiresAt = createdAt.addingTimeInterval(3600)
        sessionTimerExpiresAtByConversation[conversationId] = correctedExpiresAt
        if activeConversationId == conversationId {
            update { $0.sessionTimerExpiresAt = correctedExpiresAt }
        }
    }

    // Best-effort: a failed or unavailable check should never block the chat from starting, so
    // any error (network, decoding, no API configured) is treated the same as "not in maintenance".
    // True while the chat was closed at startup (maintenance, or the sales executive being inactive), so no socket
    // has ever been opened and no callbacks registered. Clearing the block must then do the first connect, not a
    // reconnect - `reconnectNow` has no room to reconnect to, and `startNewSession` would open a socket with
    // nothing listening.
    private var neverConnected = false

    // Whether the chat is closed right now, and why: the shared maintenance flag, or the sales executive being
    // INACTIVE. The two checks run side by side so the extra one adds no start-up latency, and maintenance wins
    // when both apply. Both fail open. Shown through the same fallback state maintenance uses.
    private func checkAccess() async -> String? {
        async let maintenance = checkMaintenanceMode()
        async let executive = executiveBlockMessage()
        let maintenanceMessage = await maintenance
        let executiveMessage = await executive
        return maintenanceMessage ?? executiveMessage
    }

    // The message currently on screen because of `checkAccess`, so that once the check passes it - and only it - is
    // taken down again straight away. Left to `onConnected`, a block that has cleared would keep showing until the
    // socket actually opens, and forever if that connect fails. A terminal close from the server (dealer or
    // executive deactivated mid-chat) is deliberately not touched here.
    private var accessBlockMessage: String?

    // Applies a `checkAccess` result to the screen. Returns true when the chat is closed.
    private func applyAccess(_ blocked: String?) -> Bool {
        if let blocked {
            accessBlockMessage = blocked
            handleTerminalClose(message: blocked)
            return true
        }
        if let shown = accessBlockMessage, uiState.terminalFallbackMessage == shown {
            update { $0.terminalFallbackMessage = nil }
        }
        accessBlockMessage = nil
        return false
    }

    private func executiveBlockMessage() async -> String? {
        guard let salesExecutiveGate else { return nil }
        return await salesExecutiveGate.blockedMessage()
    }

    // Opens the very first connection of this view model - see `neverConnected`.
    private func connectFirstTime() async {
        let generation = self.beginLoad()
        await self.repository.connect(
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in self?.handleEvent(event) }
            },
            onConnected: { [weak self] in
                Task { @MainActor [weak self] in self?.update { $0.isConnected = true; $0.error = nil; $0.terminalFallbackMessage = nil } }
            },
            onError: { [weak self] error in
                NSLog("[Chat360] Chat connection failed: %@", error.localizedDescription)
                Task { @MainActor [weak self] in self?.update { $0.isConnected = false; $0.isAgentTyping = false } }
            },
            onSlowConnectionChanged: { [weak self] slow in
                Task { @MainActor [weak self] in self?.update { $0.isSlowConnection = slow } }
            },
            onMessageTimedOut: { [weak self] chatMsgId in
                Task { @MainActor [weak self] in self?.handleMessageTimedOut(chatMsgId) }
            },
            onAppearanceLoaded: { [weak self] details, chatboxName in
                Task { @MainActor [weak self] in
                    self?.update {
                        $0.colorOverrides = details?.toColorOverrides()
                        $0.logoOverride = details?.toLogoOverride()
                        $0.botTitleOverride = chatboxName.flatMap { $0.isBlank ? nil : $0 }
                        $0.feedbackConfig = details?.feedback_config ?? $0.feedbackConfig
                    }
                }
            },
            onConversationStarted: { [weak self] roomId in
                guard let self else { return false }
                return await self.activateConversation(roomId: roomId, generation: generation)
            },
            onRawIncoming: { [weak self] raw in
                Task { @MainActor [weak self] in self?.cacheIncomingEnvelope(raw) }
            },
            onOpenUrl: { [weak self] url in
                Task { @MainActor [weak self] in self?.update { $0.pendingUrlToOpen = url } }
            },
            onSessionResumed: { [weak self] takeover, agent in
                Task { @MainActor [weak self] in self?.update { $0.isLiveChat = takeover; $0.assignedAgent = agent ?? $0.assignedAgent } }
            },
            onFeedbackRequested: { [weak self] in
                Task { @MainActor [weak self] in self?.update { $0.showFeedbackPrompt = true } }
            },
            onBotSettingsLoaded: { [weak self] shortcuts, languages in
                Task { @MainActor [weak self] in
                    self?.shortcuts = shortcuts
                    self?.languages = languages
                }
            },
            onSessionTimeReceived: { [weak self] createdAt in
                Task { @MainActor [weak self] in self?.handleSessionTimeReceived(createdAt) }
            },
            onTerminalClose: { [weak self] message in
                Task { @MainActor [weak self] in self?.handleTerminalClose(message: message) }
            },
            resumeBlankRoomId: BlankRoomRegistry.roomId(botId: botId)
        )
    }

    private func checkMaintenanceMode() async -> String? {
        guard let maintenanceApi else { return nil }
        guard let status = try? await maintenanceApi.fetchMaintenanceStatus(), status.isActive else { return nil }
        return status.message.isBlank ? "This service is temporarily unavailable for maintenance." : status.message
    }

    // Dealer/SE deactivated, or maintenance mode - a persistent fallback banner replaces the
    // input area (see ChatScreen), so nothing further should be interactable: stop the typing
    // indicator and the session countdown display, and disable every message's nudges/quick
    // replies the same way a new send already does (`repliesEnabled`, see `appendMessageNow`).
    // History stays visible. `terminalFallbackMessage` is cleared automatically wherever
    // `isConnected` flips back to true (the shared `onConnected` callback), whether that
    // reconnect was triggered by app-foreground or a manual retry.
    private func handleTerminalClose(message: String) {
        update { state in
            state.terminalFallbackMessage = message
            state.isConnected = false
            state.isAgentTyping = false
            state.messages = state.messages.map { m in
                var updated = m
                updated.repliesEnabled = false
                return updated
            }
        }
    }

    private func upsertLiveConversationEntry(conversationId: String, roomId: String?, title: String) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalizedTitle = String(normalizedTitle.prefix(80))
        if normalizedTitle.isBlank { normalizedTitle = "New conversation" }
        let existing = conversations.first { $0.id == conversationId }
        let entry = CachedConversationEntity(
            id: conversationId,
            botId: botId,
            roomId: roomId ?? existing?.roomId,
            title: (existing == nil || existing?.title == "New conversation") ? normalizedTitle : existing!.title,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        conversations = ([entry] + conversations.filter { $0.id != conversationId }).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func selectQuickReply(messageId: String, option: BotContent.MultiChoice.Option) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) {
                state.messages[index].repliesEnabled = false
                state.messages[index].selectedReplyIndex = option.index
            }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendQuickReply(option)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: option.text, fromUser: true))
            vm.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    public func selectRating(messageId: String, value: Int) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) {
                state.messages[index].repliesEnabled = false
                state.messages[index].selectedReplyIndex = value - 1
            }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendRating(value)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: String(value), fromUser: true))
            vm.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    public func selectAutoSuggestion(messageId: String, index: Int, text: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let i = state.messages.firstIndex(where: { $0.id == messageId }) {
                state.messages[i].repliesEnabled = false
                state.messages[i].selectedReplyIndex = index
            }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendAutoSuggestion(text)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
        }
    }

    public func updatePromptValue(messageId: String, primary: String, secondary: String = "") {
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            var current = state.messages[index].promptState ?? PromptState()
            if current.submitted { return }
            current.value = primary
            current.secondaryValue = secondary
            state.messages[index].promptState = current
        }
    }

    public func submitEmail(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), let prompt = message.promptState, !prompt.submitted else { return }
        let email = prompt.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isBlank, !InputValidators.validateTest(email), InputValidators.validateEmail(email) else { return }
        markPromptSubmitted(messageId: messageId)
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendEmail(email)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: email, fromUser: true))
        }
    }

    public func submitPhone(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .phonePrompt(let content) = message.content,
              let prompt = message.promptState, !prompt.submitted else { return }
        let countryCode = prompt.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let nationalNumber = prompt.secondaryValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = countryCode + nationalNumber
        guard !countryCode.isBlank, !nationalNumber.isBlank, InputValidators.validatePhoneNumber(combined, international: true) else { return }
        markPromptSubmitted(messageId: messageId)
        sendAfterResumingRoom { vm in
            let chatMsgId: String
            if content.splitVariable, let countryCodeVar = content.countryCodeVar {
                chatMsgId = vm.repository.sendSplitPhone(countryCode: countryCode, nationalNumber: nationalNumber, countryCodeVar: countryCodeVar)
            } else {
                chatMsgId = vm.repository.sendPhone(combined)
            }
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: combined, fromUser: true))
        }
    }

    public func selectDate(messageId: String, formattedDate: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .datePrompt(let content) = message.content,
              let prompt = message.promptState, !prompt.submitted else { return }
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            state.messages[index].promptState = PromptState(value: formattedDate, secondaryValue: prompt.secondaryValue, submitted: true)
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendDate(formattedDate: formattedDate, format: content.rules.dateFormat)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedDate, fromUser: true))
        }
    }

    public func submitTime(messageId: String, formattedTime: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), let prompt = message.promptState, !prompt.submitted else { return }
        markPromptSubmitted(messageId: messageId)
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendTime(formattedTime)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedTime, fromUser: true))
        }
    }

    private func markPromptSubmitted(messageId: String) {
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            state.messages[index].promptState?.submitted = true
        }
    }

    public func toggleCheckbox(messageId: String, index: Int) {
        update { state in
            guard let i = state.messages.firstIndex(where: { $0.id == messageId }), state.messages[i].repliesEnabled else { return }
            if state.messages[i].checkedIndices.contains(index) {
                state.messages[i].checkedIndices.remove(index)
            } else {
                state.messages[i].checkedIndices.insert(index)
            }
        }
    }

    public func submitCheckboxes(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .multiOption(let content) = message.content,
              message.repliesEnabled, !message.checkedIndices.isEmpty else { return }
        let text = content.options.filter { message.checkedIndices.contains($0.index) }.map { $0.text }.joined(separator: ", ")
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendCheckboxOptions(allOptions: content.options, checkedIndices: message.checkedIndices)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
        }
    }

    public func selectImageButton(messageId: String, card: BotContent.ImageButtons.Card, button: BotContent.ImageButtons.Button, submitType: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendImageButton(card: card, button: button, submitType: submitType)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: button.text, fromUser: true))
        }
    }

    public func selectTextCarouselReply(messageId: String, text: String, clickedIndex: Int, targetId: String?) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendTextCarouselReply(text: text, clickedIndex: clickedIndex, targetId: targetId)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
        }
    }

    public func selectWelcomeCard(messageId: String, card: BotContent.WelcomeScreen.Card, index: Int) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let i = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[i].repliesEnabled = false }
        }
        let trimmed = card.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty == false) ? trimmed! : "Card \(index + 1)"
        let ctaTargetId = (card.ctaEnabled && card.ctaType == "component" && !(card.ctaLink?.isBlank ?? true)) ? card.ctaLink : nil
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendWelcomeCard(cardTitle: text, clickedIndexOneBased: index + 1, ctaTargetId: ctaTargetId)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
        }
    }

    public func advanceFromIframe(targetId: String) {
        repository.jumpToNode(targetId: targetId)
    }

    public func selectShortcut(targetId: String, label: String) {
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendShortcut(targetId: targetId, label: label)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: label, fromUser: true))
        }
    }

    public func switchLanguage(targetId: String) {
        if let connectedConversationId, activeConversationId != connectedConversationId {
            setActiveConversationId(connectedConversationId)
        }
        if !uiState.isConnected { repository.reconnectNow() }
        streamRawText.removeAll()
        update {
            $0.messages = []
            $0.isAgentTyping = false
            $0.isLiveChat = false
            $0.assignedAgent = nil
            $0.isArchived = false
            $0.needsNewSession = false
            $0.showFeedbackPrompt = false
        }
        repository.jumpToNode(targetId: targetId)
    }

    public func refreshConnection() {
        Task { [weak self] in
            guard let self else { return }
            if self.applyAccess(await self.checkAccess()) { return }
            if self.neverConnected {
                self.neverConnected = false
                await self.connectFirstTime()
            } else {
                self.repository.reconnectNow()
            }
        }
    }

    public func onAppForegrounded() {
        let conversationId = activeConversationId
        let roomId = connectedRoomId
        let isActiveConversationConnected = conversationId != nil && conversationId == connectedConversationId
        Task { [weak self] in
            guard let self else { return }
            if self.applyAccess(await self.checkAccess()) { return }
            if self.neverConnected {
                self.neverConnected = false
                await self.connectFirstTime()
            } else if !self.uiState.isConnected {
                self.repository.reconnectNow()
            }
            // The socket can be silently suspended by iOS for the whole time the app was
            // backgrounded (with or without a formal disconnect ever being reported), so a reply
            // generated during that window can be missed even though we never technically
            // "switched away" from this room. If we still owe this conversation a reply, go check
            // the server for it directly rather than assuming nothing happened while we were away.
            guard isActiveConversationConnected, let conversationId, let roomId else { return }
            await self.backfillIfReplyPending(conversationId: conversationId, roomId: roomId, generation: self.loadGeneration)
        }
    }

    public func updateFormField(messageId: String, fieldIndex: Int, value: String) {
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            var current = state.messages[index].formState ?? FormState()
            if current.submitted { return }
            current.values[fieldIndex] = value
            state.messages[index].formState = current
        }
    }

    public func uploadFormField(messageId: String, bytes: Data, fieldIndex: Int, fileName: String, mimeType: String) {
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            var current = state.messages[index].formState ?? FormState()
            current.uploadingFields.insert(fieldIndex)
            state.messages[index].formState = current
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.repository.uploadFormMedia(fileBytes: bytes, fileName: fileName, mimeType: mimeType, onProgress: { _ in })
                self.update { state in
                    guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
                    var current = state.messages[index].formState ?? FormState()
                    current.values[fieldIndex] = url
                    current.fileNames[fieldIndex] = fileName
                    current.uploadingFields.remove(fieldIndex)
                    state.messages[index].formState = current
                }
            } catch {
                self.update { state in
                    guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
                    state.messages[index].formState?.uploadingFields.remove(fieldIndex)
                }
            }
        }
    }

    public func submitForm(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), case .form(let form) = message.content else { return }
        var formState = message.formState ?? FormState()
        if formState.submitted { return }
        let hasErrors = form.fields.contains { FormFieldValidator.validate($0, value: formState.values[$0.index] ?? "") != nil }
        if hasErrors {
            formState.attemptedSubmit = true
            update { state in
                if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].formState = formState }
            }
            return
        }
        formState.submitted = true
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].formState = formState }
        }
        let chatMsgId = repository.sendFormResponse(values: formState.values, fields: form.fields, fileNames: formState.fileNames)
        let ordered = form.fields.sorted { $0.index < $1.index }
        let joined = ordered.map { formState.values[$0.index] ?? "" }.joined(separator: ", ")
        let summary = joined.isBlank ? "Form submitted" : joined
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: summary, fromUser: true))
    }

    public func sendFile(bytes: Data, fileName: String, mimeType: String) {
        let message = ChatMessage(text: "", fromUser: true, attachment: Attachment(fileName: fileName))
        appendMessage(message)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.repository.uploadAndSendFile(fileBytes: bytes, fileName: fileName, mimeType: mimeType, onProgress: { percent in
                    self.updateAttachment(messageId: message.id) { $0.progress = percent }
                })
                self.updateAttachment(messageId: message.id) { $0.progress = 100; $0.uploaded = true }
            } catch {
                self.updateAttachment(messageId: message.id) { $0.failed = true }
            }
        }
    }

    public func onVoiceRecordingCaptured(filePath: String, amplitudes: [Int], durationMs: Int64) {
        update { $0.voiceDraft = VoiceDraftState(filePath: filePath, amplitudes: amplitudes, durationMs: durationMs) }
    }

    public func cancelVoiceDraft() {
        let path = uiState.voiceDraft?.filePath
        update { $0.voiceDraft = nil }
        if let path { try? FileManager.default.removeItem(atPath: path) }
    }

    public func sendVoiceDraft() {
        guard let draft = uiState.voiceDraft, !draft.uploading else { return }
        update { $0.voiceDraft?.uploading = true; $0.voiceDraft?.uploadProgress = 0; $0.voiceDraft?.error = nil }
        Task { [weak self] in
            guard let self else { return }
            do {
                let fileUrl = URL(fileURLWithPath: draft.filePath)
                let data = try Data(contentsOf: fileUrl)
                let voiceUrl = try await self.repository.uploadAndSendVoiceMessage(
                    fileBytes: data, fileName: fileUrl.lastPathComponent, mimeType: "audio/mp4", transcript: "",
                    onProgress: { percent in self.update { $0.voiceDraft?.uploadProgress = percent } }
                )
                self.appendMessage(ChatMessage(
                    text: "", fromUser: true,
                    voiceMessage: VoiceMessageInfo(localFilePath: draft.filePath, remoteUrl: voiceUrl, amplitudes: draft.amplitudes, durationMs: draft.durationMs)
                ))
                self.update { $0.voiceDraft = nil }
            } catch {
                self.update { $0.voiceDraft?.uploading = false; $0.voiceDraft?.error = "Upload failed. Try again or cancel." }
            }
        }
    }

    public func submitFeedback(rating: Int?, feedbackText: String) {
        repository.sendConfigurableFeedback(rating: rating, feedbackText: feedbackText)
        update { $0.showFeedbackPrompt = false }
    }

    public func dismissFeedbackPrompt() {
        update { $0.showFeedbackPrompt = false }
    }

    private func registerLiveBotReplyForFeedbackPrompt() {
        guard showPeriodicFeedbackPrompt else { return }
        guard let conversationId = activeConversationId else { return }
        if nextFeedbackPromptThresholdByConversation[conversationId] == nil {
            nextFeedbackPromptThresholdByConversation[conversationId] = Int.random(in: periodicFeedbackPromptInterval)
        }
        let threshold = nextFeedbackPromptThresholdByConversation[conversationId]!
        let count = (botRepliesSinceLastFeedbackPromptByConversation[conversationId] ?? 0) + 1
        botRepliesSinceLastFeedbackPromptByConversation[conversationId] = count
        NSLog("[Chat360] Feedback-prompt count: %d/%d (conversation=%@)", count, threshold, conversationId)
        guard count >= threshold else { return }
        botRepliesSinceLastFeedbackPromptByConversation[conversationId] = 0
        let nextThreshold = Int.random(in: periodicFeedbackPromptInterval)
        nextFeedbackPromptThresholdByConversation[conversationId] = nextThreshold
        NSLog("[Chat360] Showing periodic feedback prompt - next threshold=%d (conversation=%@)", nextThreshold, conversationId)
        update { $0.showPeriodicFeedbackPrompt = true }
    }

    // No dismiss counterpart by design - this dialog has no cancel/close affordance, matching
    // the requirement that it can't be skipped once shown.
    public func submitPeriodicFeedback(text: String) {
        update { $0.showPeriodicFeedbackPrompt = false }
        guard let chatHistoryRepository else {
            NSLog("[Chat360] Skipping periodic feedback submit: third-party-tasks not configured")
            return
        }
        guard let roomId = connectedRoomId else {
            NSLog("[Chat360] Skipping periodic feedback submit: no connected room")
            return
        }
        guard let sessionId = repository.currentSessionId() else {
            NSLog("[Chat360] Skipping periodic feedback submit: no session id yet")
            return
        }
        NSLog("[Chat360] Submitting periodic feedback: room=%@ session=%@ length=%d", roomId, sessionId, text.count)
        Task {
            await chatHistoryRepository.submitPeriodicFeedback(roomId: roomId, sessionId: sessionId, feedbackText: text)
        }
    }

    private func updateAttachment(messageId: String, transform: (inout Attachment) -> Void) {
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }), var attachment = state.messages[index].attachment else { return }
            transform(&attachment)
            state.messages[index].attachment = attachment
        }
    }

    private func handleMessageTimedOut(_ chatMsgId: String) {
        update { state in
            state.messages = state.messages.map { m in
                var updated = m
                if updated.chatMsgId == chatMsgId { updated.failed = true }
                return updated
            }
            state.isAgentTyping = false
        }
    }

    // Shows the last known server-configured welcome copy straight away, then refreshes it in the
    // background. Runs beside the connect and never gates it; any failure just leaves the welcome screen on
    // the host app's own text (or the theme default).
    private func loadWelcomeText(_ repository: WelcomeTextRepository?) {
        guard let repository else { return }
        if let cached = repository.cached() { uiState.welcomeOverride = cached }
        Task { [weak self] in
            if case .success(let fresh) = await repository.refresh() { self?.update { $0.welcomeOverride = fresh } }
        }
    }

    public func onInputChange(_ text: String) {
        update { $0.inputText = text }
    }

    /// Index of the selected Assistant Mode option. Published so the drawer reflects it.
    @Published public private(set) var assistantModeIndex: Int

    /// Selects an Assistant Mode option: its `variables` are merged into the session-init `meta`, and a fresh
    /// session is started so the bot sees them. A blank room is never reused, since it was created under the
    /// previous variables. No-op when `index` is already selected.
    public func selectAssistantMode(index: Int, variables: [String: String]) {
        guard index != assistantModeIndex else { return }
        assistantModeIndex = index
        repository.setAssistantVariables(variables)
        Task { [weak self] in
            guard let self else { return }
            if self.applyAccess(await self.checkAccess()) { return }
            if self.neverConnected {
                self.neverConnected = false
                await self.connectFirstTime()
                return
            }
            await self.createNewRoom()
        }
    }

    public func startNewChat() {
        Task { [weak self] in
            guard let self else { return }
            // Blocked: leave whatever conversation/history is currently on screen untouched
            // rather than wiping it into a dead new chat - just surface why via the same banner
            // used elsewhere for maintenance mode.
            if self.applyAccess(await self.checkAccess()) { return }
            if self.neverConnected {
                self.neverConnected = false
                await self.connectFirstTime()
                return
            }
            if await self.reuseBlankRoom() { return }
            await self.createNewRoom()
        }
    }

    // "New chat" while an untouched room already exists: shows that room again instead of
    // creating another. Returns false when there isn't one (or it can no longer be resumed), so
    // the caller creates a real new room as usual.
    //
    // Two shapes: the socket is still on the blank room (only the display had wandered off to a
    // browsed conversation, or the room is still being created), so nothing has to reconnect; or
    // the socket moved on to another room and the blank one is resumed via its saved session,
    // exactly like opening any older conversation.
    private func reuseBlankRoom() async -> Bool {
        if let connectedId = connectedConversationId, !conversationPersisted {
            showBlankRoom(conversationId: connectedId, envelopes: pendingRawEnvelopes)
            return true
        }
        guard let blank = blankRoom else { return false }
        showBlankRoom(conversationId: blank.conversationId, envelopes: blank.envelopes)
        update { $0.isConnected = false }
        let switched = await repository.switchToRoom(targetRoomId: blank.roomId) { [weak self] resumedRoomId in
            guard let self else { return false }
            self.connectedConversationId = blank.conversationId
            self.connectedRoomId = resumedRoomId
            self.conversationPersisted = false
            self.pendingRawEnvelopes.removeAll()
            self.blankRoom = nil
            if resumedRoomId == blank.roomId {
                self.pendingRawEnvelopes = blank.envelopes
                // The opener is already on screen from the stash; reporting history keeps the
                // repository from re-jumping to the first node and duplicating it.
                return !blank.envelopes.isEmpty
            }
            // The server handed back a different room (the saved one was gone): the stashed
            // opener belongs to a room that no longer exists, so let this fresh room render its own.
            self.update { $0.messages = [] }
            return false
        }
        if !switched {
            blankRoom = nil
            await createNewRoom()
        }
        return true
    }

    private func showBlankRoom(conversationId: String, envelopes: [String]) {
        _ = beginLoad()
        setActiveConversationId(conversationId)
        previousHistoryCursor = nil
        streamRawText.removeAll()
        update {
            $0.messages = []
            $0.isAgentTyping = false
            $0.isLiveChat = false
            $0.assignedAgent = nil
            $0.isArchived = false
            $0.needsNewSession = false
            $0.voiceDraft = nil
            $0.showFeedbackPrompt = false
            $0.pendingUrlToOpen = nil
            $0.hasMoreHistory = false
        }
        // A brand-new room has no recorded opener or user turn yet - replay exactly like it.
        cachedEarliestUserTimestampMs = nil
        cachedSuppressedOpenerNodeId = nil
        restoringFromCache = true
        for raw in envelopes {
            guard let data = raw.data(using: .utf8), let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) else { continue }
            handleEvent(envelope.toIncomingEvent())
        }
        restoringFromCache = false
    }

    private func createNewRoom() async {
        let generation = beginLoad()
        let conversationId = UUID().uuidString
        // Only the display resets now, for a responsive "new chat" screen. Live-frame routing
        // (connectedConversationId and the bookkeeping set alongside it in `beginNewRoomActivation`)
        // deliberately stays on the *old* room until its socket is really torn down: the repository
        // keeps that socket open for a reply still in flight (see awaitPendingReplyBeforeTeardown),
        // and flipping the routing here would file that reply into this brand-new, still-empty chat -
        // rendering it there and losing it from the room it belongs to.
        self.setActiveConversationId(conversationId)
        self.streamRawText.removeAll()
        self.update {
            $0.messages = []
            $0.inputText = ""
            $0.isAgentTyping = false
            $0.isConnected = false
            $0.isLiveChat = false
            $0.assignedAgent = nil
            $0.isArchived = false
            $0.needsNewSession = false
            $0.voiceDraft = nil
            $0.showFeedbackPrompt = false
            $0.pendingUrlToOpen = nil
            $0.hasMoreHistory = false
        }
        await repository.startNewSession(onConversationStarted: { [weak self] roomId in
            await self?.beginNewRoomActivation(conversationId: conversationId, roomId: roomId, generation: generation) ?? false
        })
    }

    /// Only now does routing move to the new conversation, exactly on the id already shown optimistically
    /// (`activateConversation` reads `connectedConversationId` as its cache hint).
    private func beginNewRoomActivation(conversationId: String, roomId: String, generation: Int) async -> Bool {
        connectedConversationId = conversationId
        connectedRoomId = nil
        conversationPersisted = false
        pendingRawEnvelopes.removeAll()
        return await activateConversation(roomId: roomId, generation: generation)
    }

    public func renameConversation(conversationId: String, title: String) {
        var normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalizedTitle = String(normalizedTitle.prefix(80))
        guard !normalizedTitle.isBlank else { return }
        let roomId = conversations.first { $0.id == conversationId }?.roomId
        Task { [weak self] in
            guard let self else { return }
            await self.cache.renameConversation(conversationId: conversationId, title: normalizedTitle, botId: self.botId)
            if let roomId, let chatHistoryRepository = self.chatHistoryRepository {
                await chatHistoryRepository.renameRoom(roomId: roomId, roomName: normalizedTitle)
            }
        }
    }

    public func deleteConversation(_ conversationId: String) {
        let wasConnected = conversationId == connectedConversationId
        let wasActive = conversationId == activeConversationId
        let roomId = conversations.first { $0.id == conversationId }?.roomId
        conversations = conversations.filter { $0.id != conversationId }
        Task { [weak self] in
            guard let self else { return }
            await self.cache.deleteConversation(conversationId: conversationId, botId: self.botId)
            if let roomId, let chatHistoryRepository = self.chatHistoryRepository {
                Task { await chatHistoryRepository.markRoomInactive(roomId: roomId) }
            }
            if wasConnected {
                self.startNewChat()
                return
            }
            guard wasActive else { return }
            if let fallback = self.conversations.first(where: { $0.id != conversationId }) {
                self.openConversation(fallback.id)
            } else {
                self.startNewChat()
            }
        }
    }

    private func activateConversation(roomId: String, generation: Int) async -> Bool {
        let (conversationId, hasCachedMessages) = await cache.activateForRoom(botId: botId, roomId: roomId, pendingId: connectedConversationId)
        connectedConversationId = conversationId
        connectedRoomId = roomId
        conversationPersisted = hasCachedMessages
        if hasCachedMessages {
            BlankRoomRegistry.clear(botId: botId, roomId: roomId)
        } else {
            pendingRawEnvelopes.removeAll()
            BlankRoomRegistry.set(botId: botId, roomId: roomId)
        }
        // The repository's live socket is already bound to this room (the bookkeeping above is
        // committed unconditionally, or a frame for it would be cached under the wrong
        // conversation); only what's *rendered* is allowed to bail on being overtaken.
        guard isCurrentLoad(generation) else { return hasCachedMessages }
        setActiveConversationId(conversationId)
        previousHistoryCursor = nil
        if hasCachedMessages {
            _ = await replayFromCache(conversationId: conversationId, generation: generation)
            await backfillIfReplyPending(conversationId: conversationId, roomId: roomId, generation: generation)
            return true
        }
        return await refreshConversationHistory(conversationId: conversationId, roomId: roomId, generation: generation)
    }

    // A room this device still owes a reply to (see `ReplyPendingEntity`) can't be trusted to the
    // local cache alone - whatever socket would have delivered that reply is already gone by the
    // time we're reconnecting here, whether we're switching rooms, resuming after the app was
    // killed, or reconnecting after being backgrounded. This checks the server for anything that
    // arrived while we weren't watching, without touching whatever's already correctly loaded -
    // notably, our own locally-cached sends (nudges included) are always trusted over the
    // server's echo of them, which isn't reliable for every send type.
    private func backfillIfReplyPending(conversationId: String, roomId: String, generation: Int) async {
        guard let pending = await cache.replyPending(conversationId: conversationId), isCurrentLoad(generation) else { return }
        // Derives "this is overdue" from the persisted pending record itself, before ever asking
        // the network - a restart wipes the in-memory `failed` flag along with everything else,
        // so without this a message that's genuinely long overdue would show as neither answered
        // nor failed until a fresh backfill fetch (below) came back, which could take a moment or
        // silently not happen at all if the fetch fails. This makes the correct state visible
        // immediately on reopening, then the fetch below still runs to check for a real answer.
        if nowMs() - pending.createdAt > Self.staleReplyThresholdMs {
            setMessageFailed(chatMsgId: pending.chatMsgId, failed: true)
        } else {
            // Shows the typing indicator immediately instead of leaving a silent gap while we wait
            // to find out whether the reply already arrived (live, mid-fetch) or needs recovering.
            update { $0.isAgentTyping = true }
        }
        let resolved = await backfillMissingReplies(conversationId: conversationId, roomId: roomId, pending: pending, generation: generation)
        if !resolved { pollForMissedReply(conversationId: conversationId, roomId: roomId, generation: generation) }
    }

    // How often to look again for a reply that wasn't there on the first check.
    static var missedReplyPollIntervalNs: UInt64 = 3_000_000_000

    // The reply to a message sent just before switching rooms (or leaving the screen) is generated
    // server-side anyway - the server stores it in history about 14s after the send whether or not any
    // socket is connected - but it is only *pushed* to a socket that is connected to that room at that
    // moment. Coming back sooner than that, the one check above finds nothing yet, the reconnect
    // delivers nothing (the reply was generated while this device was on another room), and nothing
    // ever looked again: the room sat at "connected" with the reply missing until it was reopened.
    //
    // So keep checking, quietly in the background, until the reply is found, a live frame delivers it
    // (which clears the pending record), this load is superseded, or the message goes stale
    // (`staleReplyThresholdMs`, which `backfillMissingReplies` turns into a "not delivered" mark).
    // Detached from the caller on purpose: it is awaited from `establishSession` while opening the
    // socket, which must not wait up to 90s on this.
    private func pollForMissedReply(conversationId: String, roomId: String, generation: Int) {
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: Self.missedReplyPollIntervalNs)
                guard let self, self.isCurrentLoad(generation),
                      let pending = await self.cache.replyPending(conversationId: conversationId) else { return }
                if await self.backfillMissingReplies(conversationId: conversationId, roomId: roomId, pending: pending, generation: generation) { return }
            }
        }
    }

    private func setMessageFailed(chatMsgId: String?, failed: Bool) {
        guard let chatMsgId else { return }
        update { state in
            state.messages = state.messages.map { m in
                var updated = m
                if updated.chatMsgId == chatMsgId { updated.failed = failed }
                return updated
            }
        }
    }

    // Reasonable slack for the fact that the pending record's timestamp comes from the device's
    // clock (captured when the user's own message was cached) while a bot node's timestamp comes
    // from the server's - a real reply generated only a couple of seconds after the message was
    // sent could otherwise appear to have happened *before* it and get silently treated as old
    // history rather than the reply being recovered, if the two clocks aren't in perfect sync.
    private static let replyClockSkewToleranceMs: Int64 = 60_000

    // Only ever adds bot messages the server has that we don't - never wipes or rebuilds the
    // existing list the way `refreshConversationHistory` does, since that would also discard
    // locally-known user sends (e.g. nudge/quick-reply selections) that the server's own history
    // doesn't always echo back as readable text.
    /// Returns true once there is nothing left to wait for - the reply was found, the message went stale, or
    /// this load was superseded - and false while the reply is still owed and worth checking for again.
    @discardableResult
    private func backfillMissingReplies(conversationId: String, roomId: String, pending: ReplyPendingEntity, generation: Int) async -> Bool {
        NSLog(
            "[Chat360] Fetching from SERVER (backfill): room=%@ pending chatMsgId=%@ createdAt=%lld",
            roomId, pending.chatMsgId ?? "nil", pending.createdAt
        )
        guard let response = try? await repository.fetchHistory(roomId: roomId) else {
            NSLog("[Chat360] SERVER fetch (backfill) failed for room=%@", roomId)
            return false
        }
        NSLog("[Chat360] SERVER returned %d history rows for room=%@", response.history.count, roomId)
        guard isCurrentLoad(generation) else { return true }
        let earliestUserTimestamp = await earliestUserTimestampMs(conversationId: conversationId, alsoConsidering: response.history)
        let suppressedOpener = await cache.suppressedOpenerNodeId(conversationId: conversationId)
        guard isCurrentLoad(generation) else { return true }
        cachedEarliestUserTimestampMs = earliestUserTimestamp
        cachedSuppressedOpenerNodeId = suppressedOpener
        var sawBotReply = false
        // Rows to persist once the replay below is done: writing them inside the loop awaited with
        // `restoringFromCache` still true, and that flag lets a live frame for the connected room
        // render into whichever conversation is on screen (see handleEvent's top guard).
        var rawsToCache: [String] = []
        restoringFromCache = true
        for item in response.history {
            let event = item.toIncomingEvent()
            guard case .botMessage(let node) = event, let ts = node.timestampMs,
                  ts >= pending.createdAt - Self.replyClockSkewToleranceMs else {
                if case .botMessage(let node) = event {
                    NSLog(
                        "[Chat360]   SERVER row skipped (too old): %@ (pending.createdAt=%lld tolerance=%lld)",
                        describeEvent(event), pending.createdAt, Self.replyClockSkewToleranceMs
                    )
                } else {
                    NSLog("[Chat360]   SERVER row: %@", describeEvent(event))
                }
                continue
            }
            sawBotReply = true
            NSLog("[Chat360]   SERVER row accepted as new reply: %@", describeEvent(event))
            handleEvent(event)
            if let data = try? encoder.encode(item), let raw = String(data: data, encoding: .utf8) {
                rawsToCache.append(raw)
            }
        }
        restoringFromCache = false
        for raw in rawsToCache {
            await cache.cacheRaw(conversationId: conversationId, rawEnvelope: raw, botId: botId)
        }
        guard isCurrentLoad(generation) else { return true }
        if sawBotReply {
            // Don't assume `handleEvent` already cleared this - it no-ops (see the node id dedup
            // check at the top of its `.botMessage` case) whenever the reply it's looking at turns
            // out to already be on screen, which leaves nothing else to turn the indicator off.
            update { $0.isAgentTyping = false }
            // Reverts the optimistic "overdue" mark from `backfillIfReplyPending` if it turns out
            // there was a real answer after all - it wasn't actually undelivered, just recovered
            // slightly later than the stale threshold assumed.
            setMessageFailed(chatMsgId: pending.chatMsgId, failed: false)
            await cache.clearReplyPending(conversationId: conversationId)
            return true
        } else if nowMs() - pending.createdAt > Self.staleReplyThresholdMs {
            setMessageFailed(chatMsgId: pending.chatMsgId, failed: true)
            update { $0.isAgentTyping = false }
            await cache.clearReplyPending(conversationId: conversationId)
            return true
        }
        return false
    }

    @discardableResult
    private func replayFromCache(conversationId: String, generation: Int) async -> Bool {
        guard isCurrentLoad(generation) else { return false }
        streamRawText.removeAll()
        update { $0.messages = []; $0.hasMoreHistory = false }
        let cachedMessages = await cache.messages(conversationId: conversationId)
        NSLog(
            "[Chat360] Replaying from LOCAL cache: conversation=%@ rows=%d (user=%d raw=%d)",
            conversationId, cachedMessages.count,
            cachedMessages.filter { $0.kind == "USER" }.count, cachedMessages.filter { $0.kind == "RAW" }.count
        )
        let earliestUserTimestamp = cachedMessages.filter { $0.kind == "USER" }.map { $0.createdAt }.min()
        let suppressedOpener = await cache.suppressedOpenerNodeId(conversationId: conversationId)
        // Both awaits above are where a newer load can overtake this one - bail before appending
        // anything, or two replays each append into the same transcript.
        guard isCurrentLoad(generation) else { return false }
        cachedEarliestUserTimestampMs = earliestUserTimestamp
        cachedSuppressedOpenerNodeId = suppressedOpener
        restoringFromCache = true
        var hasCachedMessages = false
        for cached in cachedMessages {
            hasCachedMessages = true
            switch cached.kind {
            case "USER":
                NSLog("[Chat360]   LOCAL row: USER chatMsgId=%@ text=%@", cached.chatMsgId ?? "nil", String(cached.payload.prefix(60)))
                appendMessage(ChatMessage(chatMsgId: cached.chatMsgId, text: cached.payload, fromUser: true, timeText: formatMessageTime(cached.createdAt)), cacheUserMessage: false)
            case "RAW":
                if let data = cached.payload.data(using: .utf8),
                   let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) {
                    let event = envelope.toIncomingEvent()
                    NSLog("[Chat360]   LOCAL row: RAW %@", describeEvent(event))
                    handleEvent(event)
                } else {
                    NSLog("[Chat360]   LOCAL row: RAW <failed to decode> payload=%@", String(cached.payload.prefix(120)))
                }
            default:
                break
            }
        }
        restoringFromCache = false
        return hasCachedMessages
    }

    private func describeEvent(_ event: IncomingSocketEvent) -> String {
        switch event {
        case .botMessage(let node):
            return "botMessage nodeId=\(node.nodeId ?? "nil") ts=\(node.timestampMs.map(String.init) ?? "nil") text=\(String((node.text ?? "").prefix(60)))"
        case .echoedUserMessage(let chatMsgId, let text, let ts):
            return "echoedUserMessage chatMsgId=\(chatMsgId ?? "nil") ts=\(ts.map(String.init) ?? "nil") text=\(String((text ?? "").prefix(60)))"
        case .ack(let chatMsgId):
            return "ack chatMsgId=\(chatMsgId ?? "nil")"
        case .typingStatus(let isTyping):
            return "typingStatus isTyping=\(isTyping)"
        case .inactivityNotice:
            return "inactivityNotice"
        case .agentAssigned:
            return "agentAssigned"
        case .liveChatEnded:
            return "liveChatEnded"
        case .closeConnection:
            return "closeConnection"
        case .pong:
            return "pong"
        case .unhandled:
            return "unhandled"
        }
    }

    // A pending reply that's still missing after actually asking the server for this room's
    // current state isn't just "hasn't arrived yet" forever - past this age, treat it as a real
    // failure instead of silently leaving the sent message with no visible outcome at all.
    private static let staleReplyThresholdMs: Int64 = 90_000

    @discardableResult
    private func refreshConversationHistory(conversationId: String, roomId: String, generation: Int) async -> Bool {
        NSLog("[Chat360] Fetching from SERVER (full refresh): room=%@", roomId)
        guard let response = try? await repository.fetchHistory(roomId: roomId) else {
            NSLog("[Chat360] SERVER fetch (full refresh) failed for room=%@", roomId)
            return false
        }
        let history = response.history
        NSLog("[Chat360] SERVER returned %d history rows for room=%@ (full refresh)", history.count, roomId)
        guard isCurrentLoad(generation) else { return !history.isEmpty }
        let earliestUserTimestamp = await earliestUserTimestampMs(conversationId: conversationId, alsoConsidering: history)
        let suppressedOpener = await cache.suppressedOpenerNodeId(conversationId: conversationId)
        // Awaited above - a newer load may have taken over. Checked before anything is cleared, so
        // this stale one leaves the newer one's transcript alone.
        guard isCurrentLoad(generation) else { return !history.isEmpty }
        streamRawText.removeAll()
        update { $0.messages = []; $0.isArchived = false; $0.isLiveChat = false; $0.assignedAgent = nil }
        cachedEarliestUserTimestampMs = earliestUserTimestamp
        cachedSuppressedOpenerNodeId = suppressedOpener
        restoringFromCache = true
        var sawBotReply = false
        for item in history {
            let event = item.toIncomingEvent()
            NSLog("[Chat360]   SERVER row: %@", describeEvent(event))
            if case .botMessage = event { sawBotReply = true }
            handleEvent(event)
        }
        restoringFromCache = false
        await cache.replaceRawHistory(conversationId: conversationId, history: history)
        if sawBotReply {
            await cache.clearReplyPending(conversationId: conversationId)
        } else if let pending = await cache.replyPending(conversationId: conversationId),
                  nowMs() - pending.createdAt > Self.staleReplyThresholdMs {
            setMessageFailed(chatMsgId: pending.chatMsgId, failed: true)
            await cache.clearReplyPending(conversationId: conversationId)
        }
        guard isCurrentLoad(generation) else { return !history.isEmpty }
        previousHistoryCursor = response.previous_cursor
        update { $0.hasMoreHistory = response.previous_cursor != nil }
        return !history.isEmpty
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // The earliest real user-message timestamp for this conversation, combining local cache
    // (reliable for every send type, nudges included - see `markReplyPending`'s own reasoning)
    // with whatever a freshly fetched batch of server history adds - `nil` if neither has one.
    // Used to seed `cachedEarliestUserTimestampMs` before a replay/refresh/backfill pass; see its
    // read site in `handleEvent` for why this needs to be an actual point in time, not a yes/no
    // fact. Local cache is consulted directly rather than `uiState.messages`, since a user-
    // authored `ChatMessage` doesn't carry a `timestampMs` today - only bot messages do.
    private func earliestUserTimestampMs(conversationId: String, alsoConsidering history: [RawSocketEnvelope] = []) async -> Int64? {
        let fromCache = await cache.messages(conversationId: conversationId).filter { $0.kind == "USER" }.map { $0.createdAt }
        let fromHistory = history.compactMap { envelope -> Int64? in
            guard case .echoedUserMessage(_, _, let timestampMs) = envelope.toIncomingEvent() else { return nil }
            return timestampMs
        }
        return (fromCache + fromHistory).min()
    }

    public func loadMoreHistory() {
        guard let conversationId = activeConversationId,
              let roomId = conversations.first(where: { $0.id == conversationId })?.roomId,
              let cursor = previousHistoryCursor,
              !uiState.isLoadingMoreHistory else { return }
        update { $0.isLoadingMoreHistory = true }
        // Paging within the conversation already on screen, not a new load - but it must still notice
        // that a switch (even one that comes back to this same conversation) happened while it awaited.
        let generation = loadGeneration
        Task { [weak self] in
            guard let self else { return }
            guard let response = try? await self.repository.fetchMoreHistory(roomId: roomId, cursor: cursor), self.activeConversationId == conversationId, self.isCurrentLoad(generation) else {
                self.update { $0.isLoadingMoreHistory = false }
                return
            }
            let earliestUserTimestamp = await self.earliestUserTimestampMs(conversationId: conversationId, alsoConsidering: response.history)
            let suppressedOpener = await self.cache.suppressedOpenerNodeId(conversationId: conversationId)
            guard self.isCurrentLoad(generation) else {
                self.update { $0.isLoadingMoreHistory = false }
                return
            }
            let sizeBefore = self.uiState.messages.count
            self.cachedEarliestUserTimestampMs = earliestUserTimestamp
            self.cachedSuppressedOpenerNodeId = suppressedOpener
            self.restoringFromCache = true
            for item in response.history { self.handleEvent(item.toIncomingEvent()) }
            self.restoringFromCache = false
            self.update { state in
                let olderMessages = Array(state.messages.dropFirst(sizeBefore))
                let existingMessages = Array(state.messages.prefix(sizeBefore))
                state.messages = olderMessages + existingMessages
                state.isLoadingMoreHistory = false
                state.hasMoreHistory = response.previous_cursor != nil
            }
            self.previousHistoryCursor = response.previous_cursor
        }
    }

    private func cacheIncomingEnvelope(_ raw: String) {
        guard let conversationId = connectedConversationId else { return }
        var isRenderableBotEvent = false
        if let data = raw.data(using: .utf8), let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) {
            switch envelope.toIncomingEvent() {
            case .botMessage, .inactivityNotice: isRenderableBotEvent = true
            default: break
            }
        }
        guard isRenderableBotEvent else { return }
        // This fires for every bot event on the connected room regardless of which conversation
        // is currently being viewed - `handleEvent`'s own rendering is gated on that (see its top
        // guard), but bookkeeping "did this room get its reply" shouldn't be. Without this, a
        // reply that arrives while you're looking at a different conversation gets cached
        // correctly but leaves that room thinking it's still owed one, even after you've already
        // seen the reply via a later replay.
        let cache = self.cache
        let botId = self.botId
        Task {
            await cache.clearReplyPending(conversationId: conversationId)
        }
        if !conversationPersisted {
            pendingRawEnvelopes.append(raw)
            return
        }
        // Captured strongly (not [weak self]): this write must survive a fast
        // ViewModel/view teardown racing the incoming envelope, otherwise a
        // conversation can end up with only the locally authored user messages
        // and silently miss the bot's reply.
        Task {
            await cache.cacheRaw(conversationId: conversationId, rawEnvelope: raw, botId: botId)
        }
    }

    private func ensureConversationPersisted(conversationId: String, roomId: String?) async {
        if conversationPersisted { return }
        await cache.ensureConversationPersisted(botId: botId, conversationId: conversationId, roomId: roomId)
        conversationPersisted = true
        if blankRoom?.conversationId == conversationId { blankRoom = nil }
        BlankRoomRegistry.clear(botId: botId, roomId: connectedRoomId)
        for raw in pendingRawEnvelopes {
            await cache.cacheRaw(conversationId: conversationId, rawEnvelope: raw, botId: botId)
        }
        pendingRawEnvelopes.removeAll()
    }

    public func openConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else { return }
        let generation = beginLoad()
        setActiveConversationId(conversationId)
        previousHistoryCursor = nil
        update { $0.isArchived = false; $0.needsNewSession = false; $0.isLiveChat = false; $0.assignedAgent = nil; $0.isAgentTyping = false }
        let roomId = conversations.first { $0.id == conversationId }?.roomId
        Task { [weak self] in
            guard let self else { return }
            await self.restoreConversation(conversationId: conversationId, roomId: roomId, generation: generation)
        }
        // Reconnect the live socket to this room right away rather than waiting for the user's
        // next send - otherwise the socket stays bound to the previously-viewed room until then,
        // so a reply typed immediately after switching could still land in the wrong room's
        // history for the brief window before it resumes. Skipped while the maintenance/dealer
        // fallback banner is up: `repository.connect()` is never called in that state (see the
        // maintenance gate ahead of it), so none of its callbacks are wired - reconnecting here
        // would silently open a live socket/session nothing is listening to instead of leaving
        // the fallback state alone.
        guard uiState.terminalFallbackMessage == nil else { return }
        Task { [weak self] in
            await self?.switchToActiveRoomIfResumable(generation: generation)
        }
    }

    private func restoreConversation(conversationId: String, roomId: String?, generation: Int) async {
        let hasCachedMessages = await replayFromCache(conversationId: conversationId, generation: generation)
        guard isCurrentLoad(generation) else { return }
        if !hasCachedMessages, let roomId {
            _ = await refreshConversationHistory(conversationId: conversationId, roomId: roomId, generation: generation)
            return
        }
        // Same reasoning as `activateConversation` - a conversation still owed a reply is never
        // fully trusted to its local cache, since whatever would have delivered that reply is
        // already gone by the time the user taps back into it from history. Backfilling instead
        // of a full refetch keeps whatever's already correctly loaded (e.g. a nudge/quick-reply
        // selection the server's own history doesn't echo back the same way typed text does).
        if let roomId {
            await backfillIfReplyPending(conversationId: conversationId, roomId: roomId, generation: generation)
        }
    }

    public func sendMessage() {
        let text = uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if uiState.needsNewSession {
            sendInNewSession(text)
            return
        }
        if text.isEmpty && !uiState.isLiveChat { return }
        update { $0.inputText = "" }
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendFreeText(text)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
            vm.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    /// The user sent from an older room with no saved session. It can't be rejoined (the backend ignores a
    /// bare `room_id` and allocates a fresh room), and sending into whichever room happens to be connected
    /// would merge two chats - so start a new session, wait for it to connect, and send the text there.
    private func sendInNewSession(_ text: String) {
        guard !text.isEmpty else { return }
        update { $0.inputText = "" }
        Task { [weak self] in
            guard let self else { return }
            if await !self.reuseBlankRoom() { await self.createNewRoom() }
            let generation = self.loadGeneration
            let deadline = Date().addingTimeInterval(Self.newSessionSendTimeout)
            while !self.uiState.isConnected && Date() < deadline { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard self.isCurrentLoad(generation) else { return }
            // Put the text back either way: sent below on success, kept for the user to retry on failure.
            self.update { $0.inputText = text }
            if self.uiState.isConnected { self.sendMessage() }
        }
    }

    // There's no dedicated "regenerate" wire message the backend understands - the safe option
    // that needs no backend change is re-sending the user message that led to this bot reply as
    // an ordinary new message, the same as if the user had retyped it, prompting a fresh response.
    public func regenerateMessage(messageId: String) {
        guard let botIndex = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard let userMessage = uiState.messages[..<botIndex].last(where: { $0.fromUser }) else { return }
        let text = userMessage.text
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendFreeText(text)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
            vm.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    // Same "re-send as a new message" pattern as regenerate above, just triggered from a failed
    // user message instead of a bot reply - covers a plain delivery-ack timeout and a room found
    // still owed a reply after the app was restarted/backgrounded mid-generation, since both
    // converge on the same `message.failed` flag (see `UserMessageRow`).
    public func retryFailedMessage(messageId: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.fromUser, message.failed else { return }
        let text = message.text
        sendAfterResumingRoom { vm in
            let chatMsgId = vm.repository.sendFreeText(text)
            vm.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
            vm.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    // Every reply to a specific bot prompt (quick reply, rating, form field, welcome card, etc.)
    // needs the live socket actually pointed at the room being viewed before it sends - otherwise
    // it silently goes out through whichever room happens to still be connected instead, and the
    // view then snaps to match wherever the message actually landed. This centralizes that
    // resume-then-send sequencing so each call site only supplies what's different about it.
    private func sendAfterResumingRoom(_ body: @escaping (ChatViewModel) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await self.resumeActiveRoomWithTimeout()
            body(self)
        }
    }

    // Bounds switchToActiveRoomIfResumable() by a hard timeout so a slow/stuck resume (e.g. the
    // getSession round trip taking unusually long right after reopening an old room) can never
    // leave a tapped quick reply/nudge/prompt stuck behind an indefinite loader with the reply
    // never actually sent or appended as a bubble. `body` still runs afterward either way - same
    // tolerance sendFreeText already has for sending while not (yet) reconnected, where
    // AckTracker retries the send instead of the caller blocking on connectivity.
    private static let resumeRoomTimeoutNs: UInt64 = 10_000_000_000
    private func resumeActiveRoomWithTimeout() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.switchToActiveRoomIfResumable() }
            group.addTask { try? await Task.sleep(nanoseconds: Self.resumeRoomTimeoutNs) }
            await group.next()
            group.cancelAll()
        }
    }

    private func switchToActiveRoomIfResumable(generation: Int? = nil) async {
        // Callers that just began a load pass its generation; the resume-before-send path isn't a
        // new load, so it takes whatever is current now (captured before the first await below).
        let generation = generation ?? loadGeneration
        guard let active = activeConversationId, active != connectedConversationId else { return }
        guard let targetRoomId = conversations.first(where: { $0.id == active })?.roomId else { return }
        // Leaving a room nobody has typed in: remember it so "New chat" can come back to it
        // rather than creating another empty room (see `blankRoom`).
        if let leavingId = connectedConversationId, let leavingRoomId = connectedRoomId, !conversationPersisted {
            blankRoom = BlankRoom(conversationId: leavingId, roomId: leavingRoomId, envelopes: pendingRawEnvelopes)
        }
        update { $0.isConnected = false }
        let switched = await repository.switchToRoom(targetRoomId: targetRoomId) { [weak self] resumedRoomId in
            guard let self else { return false }
            guard resumedRoomId == targetRoomId else {
                // The backend didn't actually resume the requested room (e.g. its persisted
                // session token had expired) and allocated a different one instead. Reconcile
                // through the same cache-backed room->conversation mapping the initial connect
                // uses, instead of blindly attributing the new room to the conversation the
                // user was browsing - otherwise outgoing messages would be stamped into
                // resumedRoomId while the UI still appended them to active's thread, silently
                // splitting the conversation.
                return await self.activateConversation(roomId: resumedRoomId, generation: generation)
            }
            self.connectedConversationId = active
            self.connectedRoomId = resumedRoomId
            self.conversationPersisted = true
            return true
        }
        // No saved session for this room (e.g. a chat from another device): there is no way to rejoin it, and
        // anything sent from here used to be routed into whichever room *is* connected - merging two chats into
        // one. Sending instead starts a fresh session (see `sendMessage`), so the room stays a view of its history.
        if !switched, isCurrentLoad(generation) { update { $0.isConnected = true; $0.needsNewSession = true } }
    }

    public func onCleared() {
        _ = beginLoad() // ends any background reply polling
        conversationsObservationTask?.cancel()
        repository.disconnect()
    }

    deinit {
        conversationsObservationTask?.cancel()
    }
}
