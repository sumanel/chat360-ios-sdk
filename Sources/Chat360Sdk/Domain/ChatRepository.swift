import Foundation

enum ChatRepositoryError: Error {
    case notConnected
    case noVoiceUrlReturned
}

/// Session + connection orchestration. REST session-init must complete before the WebSocket
/// connects (ownerId/roomId only come from that response); reconnects reuse that same
/// ownerId/roomId rather than re-running session-init.
final class ChatRepository {
    private let baseUrl: String
    private let botId: String
    /// Host apps can turn conversation-history fetch off entirely.
    private let historyEnabled: Bool
    /// Host apps can turn off the bot proactively speaking first (REST conversation-starter fetch
    /// + WS jump on a brand-new session) - when false, a fresh session shows the welcome/logo
    /// screen instead, and the bot's flow only starts once the user sends their first message.
    private let conversationStarterEnabled: Bool
    private let apiService: Chat360ApiService
    private let wsClient: Chat360WebSocketClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var ownerId: String?
    private var roomId: String?
    private var currentTargetId: String?
    private var lastBotNode: BotNode?
    private var pendingInitJumpTargetId: String?
    private var suppressReconnect = false
    private var manuallyDisconnected = false
    /// The node id of the last bot-authored (not agent) message actually dispatched - a repeat of
    /// this id (e.g. a frame replayed by a reconnect) is dropped rather than shown twice.
    private var lastDispatchedBotNodeId: String?

    private var onEvent: (IncomingSocketEvent) -> Void = { _ in }
    private var onConnected: () -> Void = {}
    private var onError: (Error) -> Void = { _ in }
    private var onSlowConnectionChanged: (Bool) -> Void = { _ in }
    private var onMessageTimedOut: (String) -> Void = { _ in }
    private var onOpenUrl: (String) -> Void = { _ in }
    private var onFeedbackRequested: () -> Void = {}
    private var onAppearanceLoadedCallback: (BotAppearanceDetails?, String?) -> Void = { _, _ in }
    private var onSessionResumedCallback: (Bool, AssignedAgent?) -> Void = { _, _ in }
    /// Cache hook: given the just-established server `room_id`, looks up/creates the matching
    /// local conversation and replays it from cache if present, returning whether it did (`true`
    /// skips the REST history/conversation-starter fetch - a local cache hit already rendered
    /// content). Re-invoked by `startNewSession()` on "New chat", not just the initial `connect()`.
    private var onConversationStarted: (String) async -> Bool = { _ in false }
    /// Cache hook: every renderable raw frame (bot message / inactivity notice), handed over as
    /// the exact wire JSON string so it can be persisted and replayed later through the same
    /// `RawSocketEnvelope.toIncomingEvent()` pipeline as a live frame.
    private var onRawIncoming: (String) -> Void = { _ in }
    private var onBotSettingsLoaded: ([SessionShortcut], [SessionLanguage]) -> Void = { _, _ in }
    /// From session init's `configs.should_ask_feedback` - gates whether LiveChatEnded also closes the socket.
    private var shouldAskFeedback = false

    private lazy var heartbeat = HeartbeatManager(
        scheduler: scheduler,
        sendPing: { [weak self] in
            guard let self, let text = self.encodeToString(PingMessage(timestamp_int: Int64(Date().timeIntervalSince1970 * 1000))) else { return }
            self.wsClient.send(text)
        },
        onSlowConnectionChanged: { [weak self] in self?.onSlowConnectionChanged($0) }
    )
    private lazy var reconnectManager = ReconnectManager(scheduler: scheduler, reconnect: { [weak self] in self?.openSocket() })
    private lazy var ackTracker = AckTracker(scheduler: scheduler, onTimeout: { [weak self] in self?.onMessageTimedOut($0) })
    private let scheduler: Scheduler

    init(
        baseUrl: String,
        botId: String,
        historyEnabled: Bool = true,
        conversationStarterEnabled: Bool = true,
        apiService: Chat360ApiService? = nil,
        wsClient: Chat360WebSocketClient = Chat360WebSocketClient(),
        scheduler: Scheduler = DispatchScheduler()
    ) {
        self.baseUrl = baseUrl
        self.botId = botId
        self.historyEnabled = historyEnabled
        self.conversationStarterEnabled = conversationStarterEnabled
        self.apiService = apiService ?? Chat360ApiService(baseUrl: baseUrl)
        self.wsClient = wsClient
        self.scheduler = scheduler
    }

    func connect(
        onEvent: @escaping (IncomingSocketEvent) -> Void,
        onConnected: @escaping () -> Void,
        onError: @escaping (Error) -> Void,
        onSlowConnectionChanged: @escaping (Bool) -> Void = { _ in },
        onMessageTimedOut: @escaping (String) -> Void = { _ in },
        onAppearanceLoaded: @escaping (BotAppearanceDetails?, _ chatboxName: String?) -> Void = { _, _ in },
        onOpenUrl: @escaping (String) -> Void = { _ in },
        /// Seeds live-chat state from the session itself (takeover/assigned_user) before any
        /// history replays - lets a killed-and-reopened app resume mid-live-chat correctly
        /// instead of assuming a fresh bot-flow session.
        onSessionResumed: @escaping (_ takeover: Bool, _ agent: AssignedAgent?) -> Void = { _, _ in },
        /// Mirrors the widget's shouldAskFeedback-gated close: the session ended but is being
        /// held open (see `.liveChatEnded` below) so the UI can show the post-chat survey first.
        onFeedbackRequested: @escaping () -> Void = {},
        /// Cache hooks - see the stored-property doc comments above. Re-used by `startNewSession()`.
        onConversationStarted: @escaping (String) async -> Bool = { _ in false },
        onRawIncoming: @escaping (String) -> Void = { _ in },
        onBotSettingsLoaded: @escaping ([SessionShortcut], [SessionLanguage]) -> Void = { _, _ in }
    ) async {
        self.onEvent = onEvent
        self.onConnected = onConnected
        self.onError = onError
        self.onSlowConnectionChanged = onSlowConnectionChanged
        WindowEventBridge.registerSession { [weak self] event in self?.sendWindowEvent(event) }
        self.onMessageTimedOut = onMessageTimedOut
        self.onOpenUrl = onOpenUrl
        self.onFeedbackRequested = onFeedbackRequested
        self.onAppearanceLoadedCallback = onAppearanceLoaded
        self.onSessionResumedCallback = onSessionResumed
        self.onConversationStarted = onConversationStarted
        self.onRawIncoming = onRawIncoming
        self.onBotSettingsLoaded = onBotSettingsLoaded

        await establishSession()
    }

    /// Runs REST session-init, fetches appearance, seeds history (cache-first via
    /// `onConversationStarted`, falling back to conversation-starter content), then opens the
    /// socket. Shared by `connect()` and `startNewSession()` - both just differ in what state was
    /// reset beforehand.
    private func establishSession() async {
        do {
            // The widget derives website_url/current_url from the browser's own window.location,
            // which always points at the chat360-hosted page regardless of who embeds it - a
            // native client mimics that with the bot host itself (the backend 400s on
            // non-URL-shaped values like a bare app identifier).
            let host = hostFromBaseUrl(baseUrl)
            let session = try await apiService.getSession(
                botId: botId,
                websiteUrl: host,
                currentUrl: "\(baseUrl)/web_bot/?h=\(botId)"
            )
            ownerId = session.owner_id
            roomId = session.room_id
            currentTargetId = session.targetId
            shouldAskFeedback = session.configs?.should_ask_feedback ?? false
            onBotSettingsLoaded(session.botShortcuts, session.languages)
            // An INIT node means the flow hasn't started: after the socket opens, jump to the
            // session's targetId so the bot emits its first message. Only when the host app wants
            // the bot to speak first at all - see `conversationStarterEnabled`.
            if conversationStarterEnabled, session.nodeType == "INIT" { pendingInitJumpTargetId = session.targetId }

            let resumedAgent: AssignedAgent? = session.assigned_user.flatMap { user in
                let blank = (user.operator_name?.isEmpty ?? true) && (user.user_designation?.isEmpty ?? true) && (user.avatar?.isEmpty ?? true)
                return blank ? nil : AssignedAgent(name: user.operator_name, designation: user.user_designation, avatarUrl: user.avatar)
            }
            onSessionResumedCallback(session.takeover, resumedAgent)

            await fetchAppearance(host: host, onAppearanceLoaded: onAppearanceLoadedCallback)
            // Cache lookup first (an empty local cache falls through to the REST fetch inside the
            // ViewModel's own hook, see `ChatViewModel.activateConversation`) - the local cache is
            // the durable source of truth once it has anything, matching how the web reference
            // widget behaves (session-init seeds once, never a destructive resync).
            let hadHistory = historyEnabled ? await onConversationStarted(session.room_id) : false
            // A room with no history yet shows the conversation-starter content as the opening
            // bubbles instead of an empty welcome screen, using the exact same wire parsing as
            // any other frame. Skipped when a system-jump is about to fire (nodeType == INIT,
            // see above): that jump delivers the same first node over the socket, and running
            // both left the opening bubble appended twice - see
            // .claude/duplicate-welcome-message-rca.md. Also gated on `conversationStarterEnabled`
            // - when false, a room with no history just shows the welcome/logo screen instead.
            if conversationStarterEnabled, !hadHistory, session.nodeType != "INIT" { await loadConversationStarter() }
            openSocket()
        } catch {
            onError(error)
        }
    }

    /// Tears the current session down (socket, timers, in-flight acks) and re-runs session-init
    /// from scratch, so the backend allocates a genuinely new room instead of resuming the one
    /// `connect()`/the previous session established. Reuses whatever `onConversationStarted`/
    /// `onRawIncoming`/etc. hooks `connect()` already wired up - callers (the ViewModel) are
    /// expected to have already created the new local conversation row and pointed
    /// `activeConversationId` at it before calling this, so `onConversationStarted` binds to it
    /// instead of creating yet another one.
    func startNewSession() async {
        manuallyDisconnected = false
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()
        ownerId = nil
        roomId = nil
        currentTargetId = nil
        lastBotNode = nil
        pendingInitJumpTargetId = nil
        lastDispatchedBotNodeId = nil
        await establishSession()
    }

    /// Manual refresh/reconnect - bypasses `ReconnectManager`'s backoff and reuses the existing
    /// `ownerId`/`roomId` (unlike `startNewSession()`, which allocates a new room). No-op once the
    /// repository has been `disconnect()`-ed.
    func reconnectNow() {
        guard !manuallyDisconnected else { return }
        reconnectManager.cancel()
        heartbeat.stop()
        wsClient.close()
        openSocket()
    }

    /// Thin REST wrapper for the first (most recent) history page - `historyEnabled = false` short-circuits to an empty response.
    func fetchHistory(roomId: String) async -> HistoryResponse {
        guard historyEnabled else { return HistoryResponse() }
        return (try? await apiService.getHistory(roomId: roomId)) ?? HistoryResponse()
    }

    /// Thin REST wrapper for an older page, `cursor` from a previous response's `previous_cursor`.
    func fetchMoreHistory(roomId: String, cursor: Int) async -> HistoryResponse {
        guard historyEnabled else { return HistoryResponse() }
        return (try? await apiService.getHistory(roomId: roomId, taskType: "PREVIOUS", taskValue: cursor)) ?? HistoryResponse()
    }

    /// Best-effort like loadHistory()/fetchAppearance() - a failed/empty fetch just means no starter bubbles, never blocks connecting.
    private func loadConversationStarter() async {
        do {
            let items = try await apiService.getFirstMessages(botId: botId)
            for item in items {
                let event = item.toIncomingEvent()
                if case .botMessage(let node) = event {
                    lastBotNode = node
                    currentTargetId = node.targetId ?? currentTargetId
                }
                onEvent(event)
            }
        } catch {
            // Non-fatal - the real session's own first message still arrives once the socket opens.
        }
    }

    /// Best-effort like loadHistory(): a failed/missing appearance config just means the caller
    /// keeps whichever theme preset/custom colors it already resolved - never blocks connecting.
    private func fetchAppearance(host: String, onAppearanceLoaded: @escaping (BotAppearanceDetails?, String?) -> Void) async {
        do {
            let response = try await apiService.getBotAppearance(
                botId: botId,
                websiteUrl: host,
                subdomainUrl: "\(baseUrl)/web_bot/?h=\(botId)"
            )
            onAppearanceLoaded(response.details(using: decoder), response.chatboxname)
        } catch {
            onAppearanceLoaded(nil, nil)
        }
    }

    private func openSocket() {
        guard let oId = ownerId, let rId = roomId else { return }
        let wsScheme = baseUrl.hasPrefix("https") ? "wss" : "ws"
        let host = hostFromBaseUrl(baseUrl)
        let wsUrl = "\(wsScheme)://\(host)/ws/chat_updated/\(oId)/\(rId)"

        wsClient.connect(
            wsUrl: wsUrl,
            onOpen: { [weak self] in
                guard let self else { return }
                self.heartbeat.start()
                self.reconnectManager.onConnected()
                self.onConnected()
                if let targetId = self.pendingInitJumpTargetId {
                    self.pendingInitJumpTargetId = nil
                    self.sendSystemJump(targetId)
                }
            },
            onMessage: { [weak self] raw in self?.handleIncoming(raw) },
            onClosed: { [weak self] _, _ in self?.handleClosed() },
            onFailure: { [weak self] error in
                self?.handleClosed()
                self?.onError(error)
            }
        )
    }

    private func handleClosed() {
        heartbeat.stop()
        if !manuallyDisconnected {
            reconnectManager.scheduleReconnect(suppress: suppressReconnect)
        }
    }

    private func handleIncoming(_ raw: String) {
        guard let data = raw.data(using: .utf8), let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) else { return }
        heartbeat.onMessageReceived(isPong: envelope.type == "pong")

        let event = envelope.toIncomingEvent()
        switch event {
        case .botMessage(let node):
            // Drops a bot-authored frame whose node id repeats the last one actually dispatched -
            // e.g. a frame the server replays around a reconnect. Agent-authored (admin/operator)
            // messages are never deduped this way: a human agent can legitimately send the same
            // node/text twice in a row.
            if node.author == .bot, let nodeId = node.nodeId, nodeId == lastDispatchedBotNodeId {
                return
            }
            if node.author == .bot { lastDispatchedBotNodeId = node.nodeId }
            lastBotNode = node
            currentTargetId = node.targetId ?? currentTargetId
            handleWindowEventNode(node.content)
            // END-node side effects - not about rendering. urlMessage opens externally in
            // addition to whatever bubble/nothing the node's own text produces; end_session
            // closes the socket.
            if let endUrlMessage = node.endUrlMessage { onOpenUrl(endUrlMessage) }
            if node.endSessionRequested { disconnect() }
            onRawIncoming(raw)
        case .inactivityNotice:
            onRawIncoming(raw)
        case .ack(let chatMsgId):
            ackTracker.acknowledge(chatMsgId)
        // The server also uses the echoed end_user message itself as a delivery ack, not only
        // the explicit `ack` type.
        case .echoedUserMessage(let chatMsgId, _):
            ackTracker.acknowledge(chatMsgId)
        case .closeConnection(let suppress):
            if suppress { suppressReconnect = true }
        // Closes the socket outright unless the session is configured to ask for post-chat
        // feedback afterward.
        case .liveChatEnded:
            if !shouldAskFeedback { disconnect() } else { onFeedbackRequested() }
        default:
            break
        }
        onEvent(event)
    }

    /// A WINDOW_EVENT node's shouldSend fires the host's handleWindowEvent callback; its return
    /// value is fed straight back through the same "currently receiving" gate as an explicit
    /// `sendEventToBot()` call would use.
    private func handleWindowEventNode(_ content: BotContent) {
        guard case .windowEvent(let windowEvent) = content else {
            WindowEventBridge.setReceiving(false)
            return
        }
        WindowEventBridge.setReceiving(windowEvent.shouldReceive)
        if windowEvent.shouldSend {
            let response = WindowEventBridge.dispatchToHost(Chat360Bot.shared.handleWindowEvents, sendData: windowEvent.sendData)
            if !response.isEmpty {
                WindowEventBridge.sendToActiveSession(response)
            }
        }
    }

    /// The inbound half: an event handed to the active session becomes an outgoing message
    /// carrying it as `variables`.
    private func sendWindowEvent(_ event: [String: String]) {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object([:]),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            variables: event
        )
        sendTracked(outgoing)
    }

    /// Advances the bot flow without a user-authored message - used by IFRAME's postMessage bridge.
    func jumpToNode(_ targetId: String) {
        sendSystemJump(targetId)
    }

    private func sendSystemJump(_ targetId: String) {
        let jump = SystemJumpMessage(
            data: SystemJumpMessage.JumpData(target_id: targetId, currentUrl: "\(baseUrl)/web_bot/?h=\(botId)"),
            bot_id: botId,
            room_id: roomId
        )
        if let text = encodeToString(jump) { wsClient.send(text) }
    }

    /// Returns the generated chat_msg_id so the UI can tag its optimistic bubble for ack-timeout.
    /// Node context (currentId/nodeType/post_data) comes from the last bot node - LLM/webhook
    /// nodes won't answer without it.
    @discardableResult
    func sendFreeText(_ text: String) -> String {
        let sanitized = InputValidators.sanitizeInput(text)
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .string(sanitized),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(sanitized),
            variables: node?.variable.map { [$0: sanitized] }
        )
        return sendTracked(outgoing)
    }

    /// Answers a header shortcuts-menu tap. Unlike `jumpToNode` (a silent, untracked system jump -
    /// used for IFRAME advance/language switch), this is user-authored: sent as a real tracked
    /// message so the server records it and the resulting bubble can be marked failed on
    /// ack-timeout like any other reply. `targetId` overrides the current node's; `currentId`/
    /// `nodeType`/`variables` still come from the last bot node the same way any other reply does.
    @discardableResult
    func sendShortcut(targetId: String, label: String) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .string(label),
            bot_id: botId,
            targetId: targetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(label),
            variables: node?.variable.map { [$0: label] }
        )
        return sendTracked(outgoing)
    }

    /// Answers an EMAIL node - plain sanitized text through the same generic path as free text.
    @discardableResult
    func sendEmail(_ email: String) -> String { sendFreeText(email) }

    /// Answers a plain (non-international) PHONE node - identical to free text (no dedicated
    /// payload shape, no client-side validation).
    @discardableResult
    func sendPhone(_ value: String) -> String { sendFreeText(value) }

    /// Answers an international PHONE node with `splitVariable` set: country code and national
    /// number land in two separate variables, and `doNotUpdateVariable`/`multiple_vars` are set
    /// exactly as the widget sends them.
    @discardableResult
    func sendSplitPhone(countryCode: String, nationalNumber: String, countryCodeVar: String) -> String {
        let node = lastBotNode
        let displayValue = countryCode + nationalNumber
        var variables = [countryCodeVar: countryCode]
        if let variable = node?.variable { variables[variable] = nationalNumber }
        let outgoing = OutgoingMessage(
            message: .string(displayValue),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(displayValue),
            variables: variables,
            doNotUpdateVariable: true,
            multiple_vars: true
        )
        return sendTracked(outgoing)
    }

    /// Answers the AUTOSUGGESTION sub-case of CUSTOMINPUT - a plain-text reply of the picked choice.
    @discardableResult
    func sendAutoSuggestion(_ choice: String) -> String { sendFreeText(choice) }

    /// Answers a standalone DATE node - {type:'date', value, format}.
    @discardableResult
    func sendDate(formattedDate: String, format: String) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("date"), "value": .string(formattedDate), "format": .string(format)]),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(formattedDate),
            variables: node?.variable.map { [$0: formattedDate] }
        )
        return sendTracked(outgoing)
    }

    /// Answers a standalone TIME node - plain formatted string through the generic free-text path.
    @discardableResult
    func sendTime(_ formattedTime: String) -> String { sendFreeText(formattedTime) }

    /// Answers a MULTIPLE_CHECK_BOX node - {type:'checkbox-options', value: Bool[], text}.
    @discardableResult
    func sendCheckboxOptions(allOptions: [BotContent.MultiOption.Option], checkedIndices: Set<Int>) -> String {
        let node = lastBotNode
        let text = allOptions.filter { checkedIndices.contains($0.index) }.map(\.text).joined(separator: ", ")
        let outgoing = OutgoingMessage(
            message: .object([
                "type": .string("checkbox-options"),
                "value": .array(allOptions.map { .bool(checkedIndices.contains($0.index)) }),
                "text": .string(text),
            ]),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(text),
            variables: node?.variable.map { [$0: text] }
        )
        return sendTracked(outgoing)
    }

    /// Answers an IMAGE_BUTTON reply-type button. `submitType == "IMAGE_AND_BUTTON"` echoes the
    /// tapped card's image back as a MEDIA-type user message; web_url-type buttons never reach
    /// this (the UI opens them externally instead).
    @discardableResult
    func sendImageButton(card: BotContent.ImageButtons.Card, button: BotContent.ImageButtons.Button, submitType: String) -> String {
        let node = lastBotNode
        let message: JSONValue = submitType == "IMAGE_AND_BUTTON"
            ? .object(["type": .string("media"), "mediaLink": .string(card.imageUrl), "message": .string(button.text)])
            : .string(button.text)
        let outgoing = OutgoingMessage(
            message: message,
            bot_id: botId,
            targetId: button.targetId ?? node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            variables: node?.variable.map { [$0: (button.value ?? button.text)] },
            shouldValidate: false
        )
        return sendTracked(outgoing)
    }

    /// Answers a TEXT_CAROUSEL card/button/dynamic-pill tap - all share the same
    /// {type:'carousel-text-reply', text, clickedIndex} shape, only `targetId` differs by source.
    /// "link"-type CTA/card taps never reach this (the UI opens them externally instead).
    @discardableResult
    func sendTextCarouselReply(text: String, clickedIndex: Int, targetId: String?) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("carousel-text-reply"), "text": .string(text), "clickedIndex": .number(Double(clickedIndex))]),
            bot_id: botId,
            targetId: targetId ?? node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            variables: node?.variable.map { [$0: text] }
        )
        return sendTracked(outgoing)
    }

    /// Answers a MULTI_CHOICE node. message = {type:'multichoice-option', value: index+1, text},
    /// post_data = display text, currentId = the node's id, targetId = the clicked button's own
    /// targetId (falling back to the node's), shouldValidate = false.
    @discardableResult
    func sendQuickReply(_ option: BotContent.MultiChoice.Option) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("multichoice-option"), "value": .number(Double(option.index + 1)), "text": .string(option.text)]),
            bot_id: botId,
            targetId: option.targetId ?? node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(option.text),
            variables: node?.variable.map { [$0: option.text] },
            shouldValidate: false
        )
        return sendTracked(outgoing)
    }

    /// Uploads a file then answers the current node with it: message = {type:'file-upload',
    /// value, fileName} where value is the uploaded URL(s) joined by "\n", variable set from the
    /// node if present.
    func uploadAndSendFile(fileBytes: Data, fileName: String, mimeType: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw ChatRepositoryError.notConnected }
        let urls = try await apiService.uploadMedia(roomId: room, botId: botId, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, onProgress: onProgress)
        let value = urls.joined(separator: "\n")
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("file-upload"), "value": .string(value), "fileName": .string(fileName)]),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            variables: node?.variable.map { [$0: value] },
            shouldValidate: false
        )
        sendTracked(outgoing)
        return value
    }

    /// Uploads a recorded voice note then answers the current node with it: upload via the same
    /// media endpoint as `uploadAndSendFile`, but the outgoing message is free text (the
    /// transcript, usually empty) carrying voiceUrl/transcript in componentSpecificData rather
    /// than a `{type:'file-upload',...}` message body. Returns the uploaded URL so the UI can
    /// show the sent bubble immediately without waiting on an echo.
    func uploadAndSendVoiceMessage(fileBytes: Data, fileName: String, mimeType: String, transcript: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw ChatRepositoryError.notConnected }
        let urls = try await apiService.uploadMedia(roomId: room, botId: botId, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, onProgress: onProgress)
        guard let voiceUrl = urls.first else { throw ChatRepositoryError.noVoiceUrlReturned }
        let node = lastBotNode
        let sanitized = InputValidators.sanitizeInput(transcript)
        let outgoing = OutgoingMessage(
            message: .string(sanitized),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(sanitized),
            variables: node?.variable.map { [$0: sanitized] },
            componentSpecificData: .object(["voiceUrl": .string(voiceUrl), "transcript": .string(sanitized), "msgType": .string("VOICE_MESSAGE")])
        )
        sendTracked(outgoing)
        return voiceUrl
    }

    /// Uploads a MEDIA-type FORM field out-of-band, returning the uploaded URL - the field's own
    /// value stays local (part of the draft form) until the whole form is submitted, unlike
    /// `uploadAndSendFile` which sends immediately.
    func uploadFormMedia(fileBytes: Data, fileName: String, mimeType: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw ChatRepositoryError.notConnected }
        let urls = try await apiService.uploadMedia(roomId: room, botId: botId, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, onProgress: onProgress)
        return urls.joined(separator: "\n")
    }

    /// Answers a RATING node. Sends the plain 1-based index string through the normal free-text
    /// path - not a distinct wire shape, just free text with the current node's context attached.
    @discardableResult
    func sendRating(_ value: Int) -> String {
        let node = lastBotNode
        let text = String(value)
        let outgoing = OutgoingMessage(
            message: .string(text),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            post_data: .string(text),
            variables: node?.variable.map { [$0: text] }
        )
        return sendTracked(outgoing)
    }

    /// Answers a FORM node. message = {type: 'form-response', formValue: [...]} with one entry
    /// per field in index order, plus a variables map built from each field's own `variable`
    /// name. A MEDIA field's formValue entry is "{fileName}:-{uploadedUrl}"; its variable is
    /// still just the plain URL.
    @discardableResult
    func sendFormResponse(values: [Int: String], fields: [BotContent.Form.Field], fileNames: [Int: String] = [:]) -> String {
        let node = lastBotNode
        let ordered = fields.sorted { $0.index < $1.index }
        let formValue: [String] = ordered.map { field in
            let value = values[field.index] ?? ""
            if field.type == .media && !value.isEmpty {
                return "\(fileNames[field.index] ?? ""):-\(value)"
            }
            return value
        }
        var variables: [String: String] = [:]
        for field in ordered {
            if let variable = field.variable { variables[variable] = values[field.index] ?? "" }
        }
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("form-response"), "formValue": .array(formValue.map { .string($0) })]),
            bot_id: botId,
            targetId: node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType,
            variables: variables.isEmpty ? nil : variables
        )
        return sendTracked(outgoing)
    }

    /// Submits the post-chat configurable feedback survey: message = {rating, feedback,
    /// type:'feedback'}, nodeType: 'feedback', no targetId/currentId/variables - this is an
    /// out-of-band message, not an answer to the current flow node. `feedbackText` is the
    /// already-concatenated form-field text.
    func sendConfigurableFeedback(rating: Int?, feedbackText: String) {
        let sanitizedFeedback = InputValidators.sanitizeInput(feedbackText)
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("feedback"), "rating": .string(rating.map(String.init) ?? ""), "feedback": .string(sanitizedFeedback)]),
            bot_id: botId,
            targetId: nil,
            room_id: roomId,
            nodeType: "feedback"
        )
        sendTracked(outgoing)
        disconnect()
    }

    /// Answers a WELCOME_SCREEN card tap. `clickedIndexOneBased` is sent as a STRING (unlike
    /// TEXT_CAROUSEL's numeric clickedIndex). `ctaTargetId` overrides the node's own targetId
    /// only for `ctaType=="component"` cards; `external_link` cards still submit with the default.
    @discardableResult
    func sendWelcomeCard(cardTitle: String, clickedIndexOneBased: Int, ctaTargetId: String? = nil) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .object([
                "type": .string("welcome-card-reply"),
                "text": .string(cardTitle),
                "clickedIndex": .string(String(clickedIndexOneBased)),
                "reply_type": .string("free_text"),
            ]),
            bot_id: botId,
            targetId: ctaTargetId ?? node?.targetId ?? currentTargetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType
        )
        return sendTracked(outgoing)
    }

    @discardableResult
    private func sendTracked(_ outgoing: OutgoingMessage) -> String {
        if let text = encodeToString(outgoing) { wsClient.send(text) }
        ackTracker.trackSend(outgoing.chat_msg_id)
        return outgoing.chat_msg_id
    }

    func disconnect() {
        manuallyDisconnected = true
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()
        WindowEventBridge.unregisterSession()
    }

    private func hostFromBaseUrl(_ url: String) -> String {
        if let range = url.range(of: "://") { return String(url[range.upperBound...]) }
        return url
    }

    private func encodeToString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
