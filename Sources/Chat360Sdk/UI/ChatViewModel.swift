import Foundation

@available(iOS 13.0, *)
@MainActor
public final class ChatViewModel: ObservableObject {
    private let repository: ChatRepository
    private let botId: String
    private let cache: ChatCacheRepository
    private let chatHistoryRepository: ChatHistoryRepository?
    private let suppressInitialBotMessages: Bool

    @Published public private(set) var uiState = ChatUiState()
    @Published public private(set) var conversations: [CachedConversationEntity] = []
    @Published public private(set) var shortcuts: [String: String] = [:]
    @Published public private(set) var languages: [SessionLanguage] = []

    private var activeConversationId: String?
    private var connectedConversationId: String?
    private var connectedRoomId: String?
    private var conversationPersisted = false
    private var pendingRawEnvelopes: [String] = []
    private var restoringFromCache = false
    private var pendingSnapBackChatMsgId: String?
    private var previousHistoryCursor: Int?
    private var streamRawText: [String: String] = [:]
    private let decoder = JSONDecoder()
    private var conversationsObservationTask: Task<Void, Never>?

    public init(
        repository: ChatRepository,
        botId: String,
        cache: ChatCacheRepository,
        chatHistoryRepository: ChatHistoryRepository? = nil,
        suppressInitialBotMessages: Bool = false
    ) {
        self.repository = repository
        self.botId = botId
        self.cache = cache
        self.chatHistoryRepository = chatHistoryRepository
        self.suppressInitialBotMessages = suppressInitialBotMessages

        conversationsObservationTask = Task { [weak self] in
            guard let self else { return }
            for await list in self.cache.conversations(botId: botId) {
                self.conversations = list
            }
        }

        if let chatHistoryRepository {
            Task { [weak self] in
                guard let self else { return }
                // Don't assign the fetched list to `conversations` directly - `refreshRooms()`
                // already reconciles it into the local cache (see `syncAgentRooms`), which
                // `conversationsObservationTask` picks up via its live subscription. Writing it
                // here too raced that subscription: this one-shot assignment could land after
                // the stream's already-correct snapshot and stomp it with a narrower one, then
                // never get corrected until some unrelated local write re-fired the stream.
                let refreshed = await chatHistoryRepository.refreshRooms()
                self.update { $0.isHistoryUnavailable = refreshed == nil }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.repository.connect(
                onEvent: { [weak self] event in
                    Task { @MainActor [weak self] in self?.handleEvent(event) }
                },
                onConnected: { [weak self] in
                    Task { @MainActor [weak self] in self?.update { $0.isConnected = true; $0.error = nil } }
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
                    return await self.activateConversation(roomId: roomId)
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
                }
            )
        }
    }

    private func update(_ transform: (inout ChatUiState) -> Void) {
        transform(&uiState)
    }

    private func setActiveConversationId(_ id: String?) {
        activeConversationId = id
        update { $0.activeConversationId = id }
        Task { [weak self] in await self?.refreshPendingFeedback(conversationId: id) }
    }

    // Dislike must durably block the chat with a mandatory feedback prompt - including across
    // app restarts, conversation switches, and reopening the same room later - with no backend
    // to ask "is feedback still owed here". The local cache (already used for message/history
    // persistence) is the only thing that survives all of those, so a pending row there is the
    // source of truth this reads back from, rather than any in-memory flag.
    private func refreshPendingFeedback(conversationId: String?) async {
        guard let conversationId else {
            update { $0.pendingFeedbackMessageId = nil }
            return
        }
        let pending = await cache.pendingFeedbackMessageIds(conversationId: conversationId)
        guard activeConversationId == conversationId else { return }
        update { $0.pendingFeedbackMessageId = pending.first }
    }

    public func dislikeMessage(messageId: String) {
        guard let conversationId = activeConversationId else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.cache.markFeedbackPending(messageId: messageId, conversationId: conversationId)
            await self.refreshPendingFeedback(conversationId: conversationId)
        }
    }

    public func submitDislikeFeedback(messageId: String, text: String) {
        repository.sendConfigurableFeedback(rating: 1, feedbackText: text)
        Task { [weak self] in
            guard let self else { return }
            await self.cache.clearPendingFeedback(messageId: messageId)
            await self.refreshPendingFeedback(conversationId: self.activeConversationId)
        }
    }

    private func handleEvent(_ event: IncomingSocketEvent) {
        if !restoringFromCache && activeConversationId != connectedConversationId { return }
        switch event {
        case .botMessage(let node):
            update { $0.isAgentTyping = false }
            // Hides the bot's opening/greeting node permanently, not just before the first live
            // send - it's always present in the underlying flow (and gets replayed from cache
            // when reopening a past conversation), so the only reliable signal that it's the
            // suppressible opener rather than a real reply is that no user message exists yet.
            if suppressInitialBotMessages && !uiState.messages.contains(where: { $0.fromUser }) { return }
            if node.text == nil, case .unsupported = node.content { return }
            if case .windowEvent = node.content { return }
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
                author: node.author
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
                state.messages.append(ChatMessage(text: mergedRaw, fromUser: false, streamId: streamId))
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
            Task { [weak self] in
                guard let self else { return }
                await self.restoreConversation(conversationId: target, roomId: self.connectedRoomId)
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
                self.upsertLiveConversationEntry(conversationId: conversationId, roomId: roomId, title: message.text)
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
        let chatMsgId = repository.sendQuickReply(option)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: option.text, fromUser: true))
        update { if !$0.isLiveChat { $0.isAgentTyping = true } }
    }

    public func selectRating(messageId: String, value: Int) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) {
                state.messages[index].repliesEnabled = false
                state.messages[index].selectedReplyIndex = value - 1
            }
        }
        let chatMsgId = repository.sendRating(value)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: String(value), fromUser: true))
        update { if !$0.isLiveChat { $0.isAgentTyping = true } }
    }

    public func selectAutoSuggestion(messageId: String, index: Int, text: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let i = state.messages.firstIndex(where: { $0.id == messageId }) {
                state.messages[i].repliesEnabled = false
                state.messages[i].selectedReplyIndex = index
            }
        }
        let chatMsgId = repository.sendAutoSuggestion(text)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
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
        let chatMsgId = repository.sendEmail(email)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: email, fromUser: true))
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
        let chatMsgId: String
        if content.splitVariable, let countryCodeVar = content.countryCodeVar {
            chatMsgId = repository.sendSplitPhone(countryCode: countryCode, nationalNumber: nationalNumber, countryCodeVar: countryCodeVar)
        } else {
            chatMsgId = repository.sendPhone(combined)
        }
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: combined, fromUser: true))
    }

    public func selectDate(messageId: String, formattedDate: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }),
              case .datePrompt(let content) = message.content,
              let prompt = message.promptState, !prompt.submitted else { return }
        update { state in
            guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
            state.messages[index].promptState = PromptState(value: formattedDate, secondaryValue: prompt.secondaryValue, submitted: true)
        }
        let chatMsgId = repository.sendDate(formattedDate: formattedDate, format: content.rules.dateFormat)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedDate, fromUser: true))
    }

    public func submitTime(messageId: String, formattedTime: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), let prompt = message.promptState, !prompt.submitted else { return }
        markPromptSubmitted(messageId: messageId)
        let chatMsgId = repository.sendTime(formattedTime)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: formattedTime, fromUser: true))
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
        let chatMsgId = repository.sendCheckboxOptions(allOptions: content.options, checkedIndices: message.checkedIndices)
        let text = content.options.filter { message.checkedIndices.contains($0.index) }.map { $0.text }.joined(separator: ", ")
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    public func selectImageButton(messageId: String, card: BotContent.ImageButtons.Card, button: BotContent.ImageButtons.Button, submitType: String) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        let chatMsgId = repository.sendImageButton(card: card, button: button, submitType: submitType)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: button.text, fromUser: true))
    }

    public func selectTextCarouselReply(messageId: String, text: String, clickedIndex: Int, targetId: String?) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let index = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[index].repliesEnabled = false }
        }
        let chatMsgId = repository.sendTextCarouselReply(text: text, clickedIndex: clickedIndex, targetId: targetId)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    public func selectWelcomeCard(messageId: String, card: BotContent.WelcomeScreen.Card, index: Int) {
        guard let message = uiState.messages.first(where: { $0.id == messageId }), message.repliesEnabled else { return }
        update { state in
            if let i = state.messages.firstIndex(where: { $0.id == messageId }) { state.messages[i].repliesEnabled = false }
        }
        let trimmed = card.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty == false) ? trimmed! : "Card \(index + 1)"
        let ctaTargetId = (card.ctaEnabled && card.ctaType == "component" && !(card.ctaLink?.isBlank ?? true)) ? card.ctaLink : nil
        let chatMsgId = repository.sendWelcomeCard(cardTitle: text, clickedIndexOneBased: index + 1, ctaTargetId: ctaTargetId)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    public func advanceFromIframe(targetId: String) {
        repository.jumpToNode(targetId: targetId)
    }

    public func selectShortcut(targetId: String, label: String) {
        let chatMsgId = repository.sendShortcut(targetId: targetId, label: label)
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: label, fromUser: true))
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
            $0.showFeedbackPrompt = false
        }
        repository.jumpToNode(targetId: targetId)
    }

    public func refreshConnection() {
        repository.reconnectNow()
    }

    public func onAppForegrounded() {
        if uiState.isConnected { return }
        repository.reconnectNow()
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

    public func onInputChange(_ text: String) {
        update { $0.inputText = text }
    }

    public func startNewChat() {
        let conversationId = UUID().uuidString
        connectedConversationId = conversationId
        connectedRoomId = nil
        conversationPersisted = false
        pendingRawEnvelopes.removeAll()
        setActiveConversationId(conversationId)
        streamRawText.removeAll()
        update {
            $0.messages = []
            $0.inputText = ""
            $0.isAgentTyping = false
            $0.isConnected = false
            $0.isLiveChat = false
            $0.assignedAgent = nil
            $0.isArchived = false
            $0.voiceDraft = nil
            $0.showFeedbackPrompt = false
            $0.pendingUrlToOpen = nil
            $0.hasMoreHistory = false
        }
        Task { [weak self] in
            guard let self else { return }
            await self.repository.startNewSession(onConversationStarted: { roomId in await self.activateConversation(roomId: roomId) })
        }
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

    private func activateConversation(roomId: String) async -> Bool {
        let (conversationId, hasCachedMessages) = await cache.activateForRoom(botId: botId, roomId: roomId, pendingId: connectedConversationId)
        connectedConversationId = conversationId
        connectedRoomId = roomId
        conversationPersisted = hasCachedMessages
        if !hasCachedMessages { pendingRawEnvelopes.removeAll() }
        setActiveConversationId(conversationId)
        previousHistoryCursor = nil
        if hasCachedMessages {
            _ = await replayFromCache(conversationId: conversationId)
            return true
        }
        return await refreshConversationHistory(conversationId: conversationId, roomId: roomId)
    }

    @discardableResult
    private func replayFromCache(conversationId: String) async -> Bool {
        streamRawText.removeAll()
        update { $0.messages = []; $0.hasMoreHistory = false }
        restoringFromCache = true
        var hasCachedMessages = false
        for cached in await cache.messages(conversationId: conversationId) {
            hasCachedMessages = true
            switch cached.kind {
            case "USER":
                appendMessage(ChatMessage(chatMsgId: cached.chatMsgId, text: cached.payload, fromUser: true, timeText: formatMessageTime(cached.createdAt)), cacheUserMessage: false)
            case "RAW":
                if let data = cached.payload.data(using: .utf8),
                   let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) {
                    handleEvent(envelope.toIncomingEvent())
                }
            default:
                break
            }
        }
        restoringFromCache = false
        return hasCachedMessages
    }

    @discardableResult
    private func refreshConversationHistory(conversationId: String, roomId: String) async -> Bool {
        guard let response = try? await repository.fetchHistory(roomId: roomId) else { return false }
        let history = response.history
        if activeConversationId != conversationId { return !history.isEmpty }
        streamRawText.removeAll()
        update { $0.messages = []; $0.isArchived = false; $0.isLiveChat = false; $0.assignedAgent = nil }
        restoringFromCache = true
        for item in history { handleEvent(item.toIncomingEvent()) }
        restoringFromCache = false
        await cache.replaceRawHistory(conversationId: conversationId, history: history)
        previousHistoryCursor = response.previous_cursor
        update { $0.hasMoreHistory = response.previous_cursor != nil }
        return !history.isEmpty
    }

    public func loadMoreHistory() {
        guard let conversationId = activeConversationId,
              let roomId = conversations.first(where: { $0.id == conversationId })?.roomId,
              let cursor = previousHistoryCursor,
              !uiState.isLoadingMoreHistory else { return }
        update { $0.isLoadingMoreHistory = true }
        Task { [weak self] in
            guard let self else { return }
            guard let response = try? await self.repository.fetchMoreHistory(roomId: roomId, cursor: cursor), self.activeConversationId == conversationId else {
                self.update { $0.isLoadingMoreHistory = false }
                return
            }
            let sizeBefore = self.uiState.messages.count
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
        if !conversationPersisted {
            pendingRawEnvelopes.append(raw)
            return
        }
        // Captured strongly (not [weak self]): this write must survive a fast
        // ViewModel/view teardown racing the incoming envelope, otherwise a
        // conversation can end up with only the locally authored user messages
        // and silently miss the bot's reply.
        let cache = self.cache
        let botId = self.botId
        Task {
            await cache.cacheRaw(conversationId: conversationId, rawEnvelope: raw, botId: botId)
        }
    }

    private func ensureConversationPersisted(conversationId: String, roomId: String?) async {
        if conversationPersisted { return }
        await cache.ensureConversationPersisted(botId: botId, conversationId: conversationId, roomId: roomId)
        conversationPersisted = true
        for raw in pendingRawEnvelopes {
            await cache.cacheRaw(conversationId: conversationId, rawEnvelope: raw, botId: botId)
        }
        pendingRawEnvelopes.removeAll()
    }

    public func openConversation(_ conversationId: String) {
        guard conversationId != activeConversationId else { return }
        setActiveConversationId(conversationId)
        previousHistoryCursor = nil
        update { $0.isArchived = false; $0.isLiveChat = false; $0.assignedAgent = nil; $0.isAgentTyping = false }
        let roomId = conversations.first { $0.id == conversationId }?.roomId
        Task { [weak self] in
            guard let self else { return }
            await self.restoreConversation(conversationId: conversationId, roomId: roomId)
        }
    }

    private func restoreConversation(conversationId: String, roomId: String?) async {
        let hasCachedMessages = await replayFromCache(conversationId: conversationId)
        if !hasCachedMessages, let roomId {
            _ = await refreshConversationHistory(conversationId: conversationId, roomId: roomId)
        }
    }

    public func sendMessage() {
        let text = uiState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && !uiState.isLiveChat { return }
        update { $0.inputText = "" }
        Task { [weak self] in
            guard let self else { return }
            await self.switchToActiveRoomIfResumable()
            let chatMsgId = self.repository.sendFreeText(text)
            self.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
            self.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    // There's no dedicated "regenerate" wire message the backend understands - the safe option
    // that needs no backend change is re-sending the user message that led to this bot reply as
    // an ordinary new message, the same as if the user had retyped it, prompting a fresh response.
    public func regenerateMessage(messageId: String) {
        guard let botIndex = uiState.messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard let userMessage = uiState.messages[..<botIndex].last(where: { $0.fromUser }) else { return }
        let text = userMessage.text
        Task { [weak self] in
            guard let self else { return }
            await self.switchToActiveRoomIfResumable()
            let chatMsgId = self.repository.sendFreeText(text)
            self.appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
            self.update { if !$0.isLiveChat { $0.isAgentTyping = true } }
        }
    }

    private func switchToActiveRoomIfResumable() async {
        guard let active = activeConversationId, active != connectedConversationId else { return }
        guard let targetRoomId = conversations.first(where: { $0.id == active })?.roomId else { return }
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
                return await self.activateConversation(roomId: resumedRoomId)
            }
            self.connectedConversationId = active
            self.connectedRoomId = resumedRoomId
            self.conversationPersisted = true
            return true
        }
        if !switched { update { $0.isConnected = true } }
    }

    public func onCleared() {
        conversationsObservationTask?.cancel()
        repository.disconnect()
    }

    deinit {
        conversationsObservationTask?.cancel()
    }
}
