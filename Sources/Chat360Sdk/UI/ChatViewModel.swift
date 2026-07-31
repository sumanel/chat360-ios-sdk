import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var uiState = ChatUiState()

    private let repository: ChatRepository
    /// Raw (unrendered) text accumulated so far per streamId - chunk text arrives raw precisely
    /// so it can be concatenated as one string before RichTextParser ever sees it: a chunk
    /// boundary can land inside an HTML tag, and parsing each chunk individually would leave tag
    /// fragments as literal text. PlainTextContent re-parses this same accumulated string on
    /// every render, so no stripping happens here.
    private var streamRawText: [String: String] = [:]

    init(baseUrl: String, botId: String, historyEnabled: Bool = true) {
        self.repository = ChatRepository(baseUrl: baseUrl, botId: botId, historyEnabled: historyEnabled)
        startConnecting()
    }

    /// Test/DI seam.
    init(repository: ChatRepository) {
        self.repository = repository
        startConnecting()
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
                onFeedbackRequested: { [weak self] in self?.uiState.showFeedbackPrompt = true }
            )
        }
    }

    private func handleEvent(_ event: IncomingSocketEvent) {
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
        // Ack/echoed-user/pong only drive ChatRepository's internal bookkeeping (ack-timeout
        // cancellation, heartbeat reset) - nothing further to reflect in the UI.
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
    private func appendMessage(_ message: ChatMessage) {
        uiState.messages = uiState.messages.map { m in
            var m = m
            m.repliesEnabled = false
            return m
        }
        uiState.messages.append(message)
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
        let chatMsgId = repository.sendFreeText(text)
        uiState.inputText = ""
        appendMessage(ChatMessage(chatMsgId: chatMsgId, text: text, fromUser: true))
    }

    func disconnect() {
        repository.disconnect()
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
