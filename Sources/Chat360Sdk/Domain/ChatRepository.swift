import Foundation

@available(iOS 13.0, *)
public final class ChatRepository {
    private static let duplicateNodeWindowMs: Int64 = 2_000

    private let baseUrl: String
    private let botId: String
    private let historyEnabled: Bool
    private let apiService: Chat360ApiService
    private let wsClient: Chat360WebSocketClient
    private let sessionStore: SessionStore?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.chat360.sdk.repository"))

    private var ownerId: String?
    private var roomId: String?
    private var sessionId: String?
    private var currentTargetId: String?
    private var lastBotNode: BotNode?
    private var pendingInitJumpTargetId: String?
    private var suppressReconnect = false
    private var manuallyDisconnected = false
    private var isSocketOpen = false
    private var reconnectPending = false
    private var lastDispatchedNode: BotNode?
    private var lastDispatchedAt: Int64 = 0
    // Bumped on every establishSession() call so a slower, superseded attempt (e.g. the app's
    // own cold-start connect racing a switchToRoom triggered by an early tap) can tell it's
    // stale after its network call returns, instead of overwriting newer state or opening a
    // second, wrong socket - same idea as Chat360WebSocketClient's own generation guard.
    private var sessionGeneration: Int = 0

    private var onEvent: (IncomingSocketEvent) -> Void = { _ in }
    private var onConnected: () -> Void = {}
    private var onError: (Error) -> Void = { _ in }
    private var onSlowConnectionChanged: (Bool) -> Void = { _ in }
    private var onMessageTimedOut: (String) -> Void = { _ in }
    private var onOpenUrl: (String) -> Void = { _ in }
    private var onFeedbackRequested: () -> Void = {}
    private var onRawIncoming: (String) -> Void = { _ in }
    private var onAppearanceLoaded: (BotAppearanceDetails?, String?) -> Void = { _, _ in }
    private var onSessionResumed: (Bool, AssignedAgent?) -> Void = { _, _ in }
    private var onBotSettingsLoaded: ([String: String], [SessionLanguage]) -> Void = { _, _ in }
    private var shouldAskFeedback = false

    private lazy var heartbeat = HeartbeatManager(
        scheduler: scheduler,
        sendPing: { [weak self] in
            guard let self else { return }
            if let data = try? self.encoder.encode(PingMessage(timestamp_int: self.nowMs())), let text = String(data: data, encoding: .utf8) {
                self.wsClient.send(text)
            }
        },
        onSlowConnectionChanged: { [weak self] slow in self?.onSlowConnectionChanged(slow) }
    )
    private lazy var reconnectManager = ReconnectManager(scheduler: scheduler, reconnect: { [weak self] in self?.openSocket() })
    private lazy var ackTracker = AckTracker(scheduler: scheduler, onTimeout: { [weak self] chatMsgId in self?.onMessageTimedOut(chatMsgId) })

    public init(
        baseUrl: String,
        botId: String,
        historyEnabled: Bool = true,
        apiService: Chat360ApiService? = nil,
        wsClient: Chat360WebSocketClient = Chat360WebSocketClient(),
        sessionStore: SessionStore? = nil
    ) {
        self.baseUrl = baseUrl
        self.botId = botId
        self.historyEnabled = historyEnabled
        self.apiService = apiService ?? Chat360ApiService(baseUrl: baseUrl)
        self.wsClient = wsClient
        self.sessionStore = sessionStore
    }

    public func connect(
        onEvent: @escaping (IncomingSocketEvent) -> Void,
        onConnected: @escaping () -> Void,
        onError: @escaping (Error) -> Void,
        onSlowConnectionChanged: @escaping (Bool) -> Void = { _ in },
        onMessageTimedOut: @escaping (String) -> Void = { _ in },
        onAppearanceLoaded: @escaping (BotAppearanceDetails?, String?) -> Void = { _, _ in },
        onConversationStarted: @escaping (String) async -> Bool = { _ in false },
        onRawIncoming: @escaping (String) -> Void = { _ in },
        onOpenUrl: @escaping (String) -> Void = { _ in },
        onSessionResumed: @escaping (Bool, AssignedAgent?) -> Void = { _, _ in },
        onFeedbackRequested: @escaping () -> Void = {},
        onBotSettingsLoaded: @escaping ([String: String], [SessionLanguage]) -> Void = { _, _ in }
    ) async {
        self.onEvent = onEvent
        self.onConnected = onConnected
        self.onError = onError
        self.onSlowConnectionChanged = onSlowConnectionChanged
        WindowEventBridge.shared.registerSession { [weak self] event in self?.sendWindowEvent(event) }
        self.onMessageTimedOut = onMessageTimedOut
        self.onOpenUrl = onOpenUrl
        self.onFeedbackRequested = onFeedbackRequested
        self.onRawIncoming = onRawIncoming
        self.onAppearanceLoaded = onAppearanceLoaded
        self.onSessionResumed = onSessionResumed
        self.onBotSettingsLoaded = onBotSettingsLoaded

        // Every open of the bot starts a fresh conversation rather than silently resuming
        // whatever room was last active - the previous conversation is still reachable from
        // the history drawer, this just controls what greets the user on open.
        await establishSession(onConversationStarted: onConversationStarted)
    }

    public func startNewSession(onConversationStarted: @escaping (String) async -> Bool = { _ in false }) async {
        NSLog("[Chat360WS] Starting new session (user-initiated) - tearing down room=%@", roomId ?? "nil")
        teardownForResession()
        await establishSession(onConversationStarted: onConversationStarted)
    }

    public func switchToRoom(targetRoomId: String, onConversationStarted: @escaping (String) async -> Bool = { _ in false }) async -> Bool {
        // No local session token doesn't mean the room can't be resumed - it just means this
        // device never had a live socket session in it (e.g. it only exists because it was
        // synced down from the server's room list). Try resuming by room id alone in that case
        // rather than giving up: `getSession` already accepts room id and token as independent,
        // separately-optional values, so the server can still attach to the existing room
        // without one. If it can't, the resumedRoomId mismatch check in the caller already
        // reconciles to whatever room the server allocates instead - this can't route worse
        // than silently sending into an unrelated room the way giving up early did.
        let persisted = sessionStore?.loadForRoom(botId: botId, roomId: targetRoomId)
        NSLog("[Chat360WS] Switching to room=%@ (tearing down room=%@)", targetRoomId, roomId ?? "nil")
        teardownForResession()
        await establishSession(onConversationStarted: onConversationStarted, resumeRoomId: targetRoomId, resumeSessionToken: persisted?.sessionToken)
        return true
    }

    private func teardownForResession() {
        manuallyDisconnected = true
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()

        ownerId = nil
        roomId = nil
        sessionId = nil
        currentTargetId = nil
        lastBotNode = nil
        pendingInitJumpTargetId = nil
        shouldAskFeedback = false
    }

    private func establishSession(onConversationStarted: @escaping (String) async -> Bool, resumeRoomId: String? = nil, resumeSessionToken: String? = nil) async {
        sessionGeneration += 1
        let myGeneration = sessionGeneration
        do {
            let host = hostComponent(of: baseUrl)
            let session = try await apiService.getSession(
                botId: botId,
                websiteUrl: host,
                currentUrl: "\(baseUrl)/web_bot/?h=\(botId)",
                roomId: resumeRoomId,
                sessionId: resumeSessionToken
            )
            guard myGeneration == sessionGeneration else {
                NSLog("[Chat360WS] Discarding superseded session establish (room=%@)", session.room_id)
                return
            }
            ownerId = session.owner_id
            roomId = session.room_id
            sessionId = session.session_id
            currentTargetId = session.targetId
            NSLog("[Chat360WS] Session established: owner=%@ room=%@", session.owner_id, session.room_id)
            sessionStore?.save(botId: botId, session: PersistedSession(roomId: session.room_id, sessionToken: session.session_token, ownerId: session.owner_id))
            shouldAskFeedback = session.configs?.should_ask_feedback ?? false
            if session.nodeType == "INIT" { pendingInitJumpTargetId = session.targetId }

            var resumedAgent: AssignedAgent? = nil
            if let assignedUser = session.assigned_user {
                let hasContent = !(assignedUser.operator_name?.isBlank ?? true) || !(assignedUser.user_designation?.isBlank ?? true) || !(assignedUser.avatar?.isBlank ?? true)
                if hasContent {
                    resumedAgent = AssignedAgent(name: assignedUser.operator_name, designation: assignedUser.user_designation, avatarUrl: assignedUser.avatar)
                }
            }
            onSessionResumed(session.takeover, resumedAgent)

            var shortcuts: [String: String] = [:]
            var languages: [SessionLanguage] = []
            if let botSettings = session.bot_settings?.objectValue {
                if let shortcutsValue = botSettings["bot_shortcuts"], let data = try? encoder.encode(shortcutsValue) {
                    shortcuts = (try? decoder.decode([String: String].self, from: data)) ?? [:]
                }
                if let languagesValue = botSettings["languages"], let data = try? encoder.encode(languagesValue) {
                    languages = (try? decoder.decode([SessionLanguage].self, from: data)) ?? []
                }
            }
            onBotSettingsLoaded(shortcuts, languages)

            await fetchAppearance(host: host)
            let hadHistory = await onConversationStarted(session.room_id)
            if hadHistory {
                pendingInitJumpTargetId = nil
                // The replay above only updates the ViewModel's local cache/UI, never this
                // class's own currentTargetId/lastBotNode (those stay whatever teardownForResession
                // just reset them to) - and session.targetId can't be trusted to fill that gap on
                // a resumed room. Without this, a room whose current position is e.g. a
                // validation_error re-prompt (which itself carries no usable targetId) reconnects
                // with no known targetId at all, so the very next free-text reply goes out empty
                // and the flow can't route it. Folding through the room's recent history the same
                // way a live bot message would (see handleIncoming) recovers the last real
                // targetId before the user can send anything.
                await seedTargetContextFromHistory(roomId: session.room_id)
            } else if await loadConversationStarter() {
                pendingInitJumpTargetId = nil
            }
            guard myGeneration == sessionGeneration else { return }
            openSocket()
        } catch {
            guard myGeneration == sessionGeneration else { return }
            onError(error)
        }
    }

    public func fetchHistory(roomId: String) async throws -> HistoryResponse {
        guard historyEnabled else { return HistoryResponse() }
        return try await apiService.getHistory(roomId: roomId)
    }

    public func fetchMoreHistory(roomId: String, cursor: Int) async throws -> HistoryResponse {
        guard historyEnabled else { return HistoryResponse() }
        return try await apiService.getHistory(roomId: roomId, taskType: "PREVIOUS", taskValue: cursor)
    }

    private func loadConversationStarter() async -> Bool {
        do {
            let items = try await apiService.getFirstMessages(botId: botId)
            for item in items {
                if let data = try? encoder.encode(item), let text = String(data: data, encoding: .utf8) {
                    onRawIncoming(text)
                }
                let event = item.toIncomingEvent()
                if case .botMessage(let node) = event, !isErrorNode(node) {
                    lastBotNode = node
                    currentTargetId = node.targetId ?? currentTargetId
                }
                onEvent(event)
            }
            return !items.isEmpty
        } catch {
            return false
        }
    }

    /// Recovers `currentTargetId`/`lastBotNode` for a resumed room by folding through its most
    /// recent history the same way a live bot message would (see `handleIncoming`) - last node
    /// wins, and error nodes (see `isErrorNode`) never overwrite a real targetId already found.
    /// Best-effort like `loadConversationStarter`/`fetchAppearance`: a failed fetch just leaves
    /// whatever session-init already provided, never blocks connecting.
    private func seedTargetContextFromHistory(roomId: String) async {
        guard historyEnabled else { return }
        guard let response = try? await apiService.getHistory(roomId: roomId) else { return }
        for item in response.history {
            if case .botMessage(let node) = item.toIncomingEvent(), !isErrorNode(node) {
                lastBotNode = node
                currentTargetId = node.targetId ?? currentTargetId
            }
        }
    }

    private func fetchAppearance(host: String) async {
        do {
            let response = try await apiService.getBotAppearance(
                botId: botId,
                websiteUrl: host,
                subdomainUrl: "\(baseUrl)/web_bot/?h=\(botId)"
            )
            onAppearanceLoaded(response.details(decoder: decoder), response.chatboxname)
        } catch {
            onAppearanceLoaded(nil, nil)
        }
    }

    public func currentSessionId() -> String? {
        sessionId
    }

    public func reconnectNow() {
        guard ownerId != nil, roomId != nil else { return }
        NSLog("[Chat360WS] Manual reconnect requested (room=%@)", roomId ?? "nil")
        manuallyDisconnected = true
        reconnectManager.cancel()
        wsClient.close()
        openSocket()
    }

    private func openSocket() {
        guard let oId = ownerId, let rId = roomId else { return }
        manuallyDisconnected = false
        let wsScheme = baseUrl.hasPrefix("https") ? "wss" : "ws"
        let host = hostComponent(of: baseUrl)
        let wsUrl = "\(wsScheme)://\(host)/ws/chat_updated/\(oId)/\(rId)"
        NSLog("[Chat360WS] Opening socket for owner=%@ room=%@", oId, rId)

        wsClient.connect(
            wsUrl: wsUrl,
            onOpen: { [weak self] in
                guard let self else { return }
                NSLog("[Chat360WS] Connected (owner=%@ room=%@)", oId, rId)
                self.isSocketOpen = true
                self.reconnectPending = false
                self.heartbeat.start()
                self.reconnectManager.onConnected()
                self.onConnected()
                if let targetId = self.pendingInitJumpTargetId {
                    self.pendingInitJumpTargetId = nil
                    self.sendSystemJump(targetId: targetId)
                }
            },
            onMessage: { [weak self] raw in self?.handleIncoming(raw) },
            onClosed: { [weak self] code, reason in self?.handleClosed(code: code, reason: reason) },
            onFailure: { [weak self] error in
                self?.handleClosed(code: nil, reason: error.localizedDescription)
                self?.onError(error)
            }
        )
    }

    private func handleClosed(code: Int?, reason: String?) {
        isSocketOpen = false
        reconnectPending = false
        heartbeat.stop()
        if manuallyDisconnected {
            NSLog("[Chat360WS] Disconnected (manual, code=%@ reason=%@) - no reconnect", String(describing: code), reason ?? "")
        } else {
            NSLog("[Chat360WS] Disconnected unexpectedly (code=%@ reason=%@) - scheduling reconnect (suppressed=%@)", String(describing: code), reason ?? "", String(suppressReconnect))
            reconnectManager.scheduleReconnect(suppress: suppressReconnect)
        }
    }

    private func ensureReconnecting() {
        if isSocketOpen || reconnectPending { return }
        guard ownerId != nil, roomId != nil else { return }
        reconnectPending = true
        NSLog("[Chat360WS] Send found the socket closed - reconnecting now (room=%@)", roomId ?? "nil")
        manuallyDisconnected = true
        reconnectManager.cancel()
        wsClient.close()
        openSocket()
    }

    private func handleIncoming(_ raw: String) {
        guard let data = raw.data(using: .utf8), let envelope = try? decoder.decode(RawSocketEnvelope.self, from: data) else { return }
        if let envelopeRoomId = envelope.room_id, envelopeRoomId != roomId {
            NSLog("[Chat360WS] Dropping frame for room=%@ - no longer connected (current room=%@)", envelopeRoomId, roomId ?? "nil")
            return
        }
        heartbeat.onMessageReceived(isPong: envelope.type == "pong")

        let event = envelope.toIncomingEvent()
        let now = nowMs()
        if case .botMessage(let node) = event,
           node.author != .agent,
           node.nodeId != nil,
           node == lastDispatchedNode,
           (now - lastDispatchedAt) < Self.duplicateNodeWindowMs {
            NSLog("[Chat360WS] Duplicate bot frame dropped (redelivered): nodeId=%@", node.nodeId ?? "nil")
            return
        }
        onRawIncoming(raw)
        switch event {
        case .botMessage(let node):
            NSLog("[Chat360WS] Bot reply received: nodeId=%@ nodeType=%@ text=%@", node.nodeId ?? "nil", node.nodeType ?? "nil", node.text ?? "nil")
            lastDispatchedNode = node
            lastDispatchedAt = now
            if !isErrorNode(node) {
                lastBotNode = node
                currentTargetId = node.targetId ?? currentTargetId
            }
            handleWindowEventNode(node.content)
            if let endUrlMessage = node.endUrlMessage { onOpenUrl(endUrlMessage) }
            if node.endSessionRequested { disconnect() }
        case .ack(let chatMsgId):
            ackTracker.acknowledge(chatMsgId: chatMsgId)
        case .echoedUserMessage(let chatMsgId, _, _):
            ackTracker.acknowledge(chatMsgId: chatMsgId)
        case .closeConnection(let suppress):
            if suppress { suppressReconnect = true }
        case .liveChatEnded:
            if !shouldAskFeedback { disconnect() } else { onFeedbackRequested() }
        default:
            break
        }
        onEvent(event)
    }

    private func isErrorNode(_ node: BotNode) -> Bool {
        node.nodeType == "validation_error"
    }

    private func handleWindowEventNode(_ content: BotContent) {
        guard case .windowEvent(let windowEvent) = content else {
            WindowEventBridge.shared.setReceiving(false)
            return
        }
        WindowEventBridge.shared.setReceiving(windowEvent.shouldReceive)
        if windowEvent.shouldSend {
            let response = WindowEventBridge.shared.dispatchToHost(handleWindowEvent: Chat360Bot.shared.handleWindowEvents, sendData: windowEvent.sendData)
            if !response.isEmpty { WindowEventBridge.shared.sendToActiveSession(response) }
        }
    }

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

    public func jumpToNode(targetId: String) {
        sendSystemJump(targetId: targetId)
    }

    @discardableResult
    public func sendShortcut(targetId: String, label: String) -> String {
        let node = lastBotNode
        let outgoing = OutgoingMessage(
            message: .string(label),
            bot_id: botId,
            targetId: targetId,
            room_id: roomId,
            currentId: node?.nodeId,
            nodeType: node?.nodeType
        )
        return sendTracked(outgoing)
    }

    private func sendSystemJump(targetId: String) {
        let jump = SystemJumpMessage(
            data: SystemJumpMessage.JumpData(target_id: targetId, currentUrl: "\(baseUrl)/web_bot/?h=\(botId)"),
            bot_id: botId,
            room_id: roomId
        )
        if let data = try? encoder.encode(jump), let text = String(data: data, encoding: .utf8) {
            wsClient.send(text)
        }
    }

    @discardableResult
    public func sendFreeText(_ text: String) -> String {
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

    @discardableResult
    public func sendEmail(_ email: String) -> String { sendFreeText(email) }

    @discardableResult
    public func sendPhone(_ value: String) -> String { sendFreeText(value) }

    @discardableResult
    public func sendSplitPhone(countryCode: String, nationalNumber: String, countryCodeVar: String) -> String {
        let node = lastBotNode
        let displayValue = countryCode + nationalNumber
        var variables: [String: String] = [countryCodeVar: countryCode]
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

    @discardableResult
    public func sendAutoSuggestion(_ choice: String) -> String { sendFreeText(choice) }

    @discardableResult
    public func sendDate(formattedDate: String, format: String) -> String {
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

    @discardableResult
    public func sendTime(_ formattedTime: String) -> String { sendFreeText(formattedTime) }

    @discardableResult
    public func sendCheckboxOptions(allOptions: [BotContent.MultiOption.Option], checkedIndices: Set<Int>) -> String {
        let node = lastBotNode
        let text = allOptions.filter { checkedIndices.contains($0.index) }.map { $0.text }.joined(separator: ", ")
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

    @discardableResult
    public func sendImageButton(card: BotContent.ImageButtons.Card, button: BotContent.ImageButtons.Button, submitType: String) -> String {
        let node = lastBotNode
        let message: JSONValue
        if submitType == "IMAGE_AND_BUTTON" {
            message = .object(["type": .string("media"), "mediaLink": .string(card.imageUrl), "message": .string(button.text)])
        } else {
            message = .string(button.text)
        }
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

    @discardableResult
    public func sendTextCarouselReply(text: String, clickedIndex: Int, targetId: String?) -> String {
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

    @discardableResult
    public func sendQuickReply(_ option: BotContent.MultiChoice.Option) -> String {
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

    public func uploadAndSendFile(fileBytes: Data, fileName: String, mimeType: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw Chat360RepositoryError.notConnected }
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

    public func uploadAndSendVoiceMessage(fileBytes: Data, fileName: String, mimeType: String, transcript: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw Chat360RepositoryError.notConnected }
        let urls = try await apiService.uploadMedia(roomId: room, botId: botId, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, onProgress: onProgress)
        guard let voiceUrl = urls.first else { throw Chat360RepositoryError.uploadFailed }
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

    public func uploadFormMedia(fileBytes: Data, fileName: String, mimeType: String, onProgress: @escaping (Int) -> Void) async throws -> String {
        guard let room = roomId else { throw Chat360RepositoryError.notConnected }
        let urls = try await apiService.uploadMedia(roomId: room, botId: botId, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, onProgress: onProgress)
        return urls.joined(separator: "\n")
    }

    @discardableResult
    public func sendRating(_ value: Int) -> String {
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

    @discardableResult
    public func sendFormResponse(values: [Int: String], fields: [BotContent.Form.Field], fileNames: [Int: String] = [:]) -> String {
        let node = lastBotNode
        let ordered = fields.sorted { $0.index < $1.index }
        let formValue: [String] = ordered.map { field in
            let value = values[field.index] ?? ""
            if field.type == .media && !value.isBlank {
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

    // `endSession` defaults to true for the original end-of-conversation feedback form, where
    // the user is considered done chatting and tearing the socket down afterward is correct.
    // The per-message dislike-feedback flow reuses this same send path but passes false - the
    // user is still mid-conversation, and disconnecting there was silently killing the live
    // socket (no reconnect scheduled, heartbeat stopped, window-event bridge unregistered)
    // right before the next message they send.
    public func sendConfigurableFeedback(rating: Int?, feedbackText: String, endSession: Bool = true) {
        let sanitizedFeedback = InputValidators.sanitizeInput(feedbackText)
        let outgoing = OutgoingMessage(
            message: .object(["type": .string("feedback"), "rating": .string(rating.map { String($0) } ?? ""), "feedback": .string(sanitizedFeedback)]),
            bot_id: botId,
            targetId: nil,
            room_id: roomId,
            nodeType: "feedback"
        )
        sendTracked(outgoing)
        if endSession { disconnect() }
    }

    @discardableResult
    public func sendWelcomeCard(cardTitle: String, clickedIndexOneBased: Int, ctaTargetId: String? = nil) -> String {
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
        NSLog("[Chat360WS] User message sent: chat_msg_id=%@ nodeType=%@ targetId=%@", outgoing.chat_msg_id, outgoing.nodeType ?? "nil", outgoing.targetId ?? "nil")
        guard let data = try? encoder.encode(outgoing), let payload = String(data: data, encoding: .utf8) else { return outgoing.chat_msg_id }
        if !wsClient.send(payload) { ensureReconnecting() }
        ackTracker.trackSend(chatMsgId: outgoing.chat_msg_id) { [weak self] in
            guard let self else { return }
            if !self.wsClient.send(payload) { self.ensureReconnecting() }
        }
        return outgoing.chat_msg_id
    }

    public func disconnect() {
        NSLog("[Chat360WS] Disconnecting (manual, final) - room=%@", roomId ?? "nil")
        manuallyDisconnected = true
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()
        WindowEventBridge.shared.unregisterSession()
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func hostComponent(of url: String) -> String {
        guard let range = url.range(of: "://") else { return url }
        return String(url[range.upperBound...])
    }
}

public enum Chat360RepositoryError: Error {
    case notConnected
    case uploadFailed
}
