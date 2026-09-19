import Foundation

@available(iOS 13.0, *)
public final class ChatRepository {
    private static let duplicateNodeWindowMs: Int64 = 2_000
    // Max time a room switch/new chat will wait for an in-flight bot reply to finish before
    // tearing down the old socket anyway - see awaitPendingReplyBeforeTeardown().
    private static let pendingReplyAwaitTimeoutMs: Int64 = 10_000
    // How fresh a resumed session's created_at can be before it's treated as synthetic (the
    // backend minting a brand new one for this very query) rather than its true start time - see
    // awaitingImmediateSessionTimeCheck.
    private static let freshlyCreatedSessionWindowSeconds: TimeInterval = 15

    private let baseUrl: String
    private let botId: String
    private let historyEnabled: Bool
    private let apiService: Chat360ApiService
    private let wsClient: Chat360WebSocketClient
    private let sessionStore: SessionStore?
    /// Host-supplied key/value pairs (`Chat360Config.meta`), forwarded to session-init so the
    /// flow's `@`-variables are pre-seeded the same way the legacy WebView path gets for free
    /// via `/web_bot?h=...&meta=...` (see `Chat360Config.createUrl()`). See
    /// `Chat360ApiService.getSession`.
    private let meta: [String: String]?
    /// Dealer / employee context, forwarded to session-init as the `dealer_id` / `emp_id`
    /// query params (not via `meta`). See `Chat360ApiService.getSession`.
    private let dealerId: String?
    private let empId: String?

    // Guards the check-then-act sequences over the socket/session state above (`Locked` only makes
    // each single access atomic): ensureReconnecting's "is a reconnect already underway? -> start
    // one", the close-then-reopen in reconnectNow/teardown, the reset-and-connect in openSocket,
    // and everything a socket callback does. Recursive because those sequences call each other, and
    // `wsClient.close()` reports back synchronously into `handleClosed`. Never held across an
    // `await`, and lock order is always stateLock -> a `Locked` property or the socket client's own
    // lock (never the reverse), so it can't deadlock.
    private let stateLock = NSRecursiveLock()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.chat360.sdk.repository"))

    @Locked private var ownerId: String?
    @Locked private var roomId: String?
    @Locked private var sessionId: String?
    @Locked private var currentTargetId: String?
    @Locked private var lastBotNode: BotNode?
    @Locked private var pendingInitJumpTargetId: String?
    @Locked private var suppressReconnect = false
    @Locked private var manuallyDisconnected = false
    @Locked private var isSocketOpen = false
    @Locked private var reconnectPending = false
    @Locked private var lastDispatchedNode: BotNode?
    @Locked private var lastDispatchedAt: Int64 = 0
    // Bumped on every establishSession() call so a slower, superseded attempt (e.g. the app's
    // own cold-start connect racing a switchToRoom triggered by an early tap) can tell it's
    // stale after its network call returns, instead of overwriting newer state or opening a
    // second, wrong socket - same idea as Chat360WebSocketClient's own generation guard.
    @Locked private var sessionGeneration: Int = 0
    // Serializes connect()/startNewSession()/switchToRoom() end to end (teardown through
    // openSocket()) - without this, two of them can interleave at a suspension point (e.g. both
    // awaiting apiService.getSession()) and race on ownerId/roomId/sessionId/etc below, so
    // whichever HTTP response lands last wins even if it was requested first - the exact
    // "switching rooms during bot loading" corruption this class exists to prevent for live-frame
    // routing. A second caller simply waits for the first to fully finish instead.
    private let sessionMutex = AsyncMutex()
    // True whenever the bot's reply to the most recently sent user message hasn't fully arrived
    // yet - checked by awaitPendingReplyBeforeTeardown so switching rooms/starting a new chat
    // never closes the socket out from under a reply still being generated server-side for the
    // room being left.
    @Locked private var hasPendingReply = false
    // True once this room has ever had a session_time worth trusting server-side - either it was
    // resumed with existing history (set by establishSession) or its first live bot reply has
    // already come in on some earlier connection (set by the botMessage branch below). Reset only
    // when the room itself changes (see teardownForResession) - a reconnect of the same still-live
    // room keeps it set, so every reconnect can immediately ask and trust the answer.
    @Locked private var sessionEverStarted = false
    // Set every time a new socket connection opens for a room with no trustworthy session_time
    // yet (!sessionEverStarted) - cleared the moment a bot reply actually arrives live on that
    // connection, at which point requestSessionTime() is sent for the first time. A genuinely new
    // room has no session_time to ask about until the user sends something and the bot replies.
    @Locked private var awaitingFirstBotReplySessionTime = false
    // Set right before awaitingFirstBotReplySessionTime fires its requestSessionTime() call - the
    // very first live bot reply this room has ever had. Consumed on the matching session-time
    // reply to substitute "now" for the server's created_at, so a brand new conversation's timer
    // always starts counting down from a clean 59:59 rather than whatever the server's
    // created_at/round-trip latency would otherwise show.
    @Locked private var overrideNextSessionTimeWithNow = false
    // Set right before openSocket's onOpen asks immediately because sessionEverStarted is already
    // true (a resumed room, or a reconnect of a room already past its first reply). Consumed on
    // the matching session-time reply: a created_at within the last freshlyCreatedSessionWindow
    // means the backend just minted a brand new one for this very query (an expired/stale session
    // gets silently renewed, not returned as its true old start time) - not trustworthy yet, so
    // the reply is held back instead (see pendingSessionResetOnNextBotMessage).
    @Locked private var awaitingImmediateSessionTimeCheck = false
    // Set right before each requestSessionTime() call, cleared the moment any session-time frame
    // arrives. Lets handleSessionTimeReceived tell a reply to our own request apart from a
    // session-time frame the backend pushes unprompted.
    @Locked private var awaitingSessionTimeResponse = false
    // Set when a session-time reply shouldn't be shown to the UI the moment it arrives - either an
    // unprompted push (the backend rolls the current session over to a fresh one once its hour
    // window lapses) or a resumed session whose real elapsed time was already found to be
    // synthetic. Either way the reset should only become visible once the bot's next reply
    // actually comes in, same as overrideNextSessionTimeWithNow's first message.
    @Locked private var pendingSessionResetOnNextBotMessage = false

    @Locked private var onEvent: (IncomingSocketEvent) -> Void = { _ in }
    @Locked private var onConnected: () -> Void = {}
    @Locked private var onError: (Error) -> Void = { _ in }
    @Locked private var onSlowConnectionChanged: (Bool) -> Void = { _ in }
    @Locked private var onMessageTimedOut: (String) -> Void = { _ in }
    @Locked private var onOpenUrl: (String) -> Void = { _ in }
    @Locked private var onFeedbackRequested: () -> Void = {}
    @Locked private var onRawIncoming: (String) -> Void = { _ in }
    @Locked private var onAppearanceLoaded: (BotAppearanceDetails?, String?) -> Void = { _, _ in }
    @Locked private var onSessionResumed: (Bool, AssignedAgent?) -> Void = { _, _ in }
    @Locked private var onBotSettingsLoaded: ([String: String], [SessionLanguage]) -> Void = { _, _ in }
    @Locked private var onSessionTimeReceived: (Date) -> Void = { _ in }
    @Locked private var onTerminalClose: (String) -> Void = { _ in }
    @Locked private var shouldAskFeedback = false

    // Built once in `init` rather than `lazy`: a lazy property's first access is not thread-safe,
    // and these are first touched from whichever thread gets there first.
    private var heartbeat: HeartbeatManager!
    private var reconnectManager: ReconnectManager!
    private var ackTracker: AckTracker!

    public init(
        baseUrl: String,
        botId: String,
        historyEnabled: Bool = true,
        apiService: Chat360ApiService? = nil,
        wsClient: Chat360WebSocketClient = Chat360WebSocketClient(),
        sessionStore: SessionStore? = nil,
        meta: [String: String]? = nil,
        dealerId: String? = nil,
        empId: String? = nil
    ) {
        self.baseUrl = baseUrl
        self.botId = botId
        self.historyEnabled = historyEnabled
        self.apiService = apiService ?? Chat360ApiService(baseUrl: baseUrl)
        self.wsClient = wsClient
        self.sessionStore = sessionStore
        self.meta = meta
        self.dealerId = dealerId
        self.empId = empId
        heartbeat = HeartbeatManager(
            scheduler: scheduler,
            sendPing: { [weak self] in
                guard let self else { return }
                if let data = try? self.encoder.encode(PingMessage(timestamp_int: self.nowMs())), let text = String(data: data, encoding: .utf8) {
                    self.wsClient.send(text)
                }
            },
            onSlowConnectionChanged: { [weak self] slow in self?.onSlowConnectionChanged(slow) }
        )
        reconnectManager = ReconnectManager(scheduler: scheduler, reconnect: { [weak self] in self?.openSocket() })
        ackTracker = AckTracker(scheduler: scheduler, onTimeout: { [weak self] chatMsgId in self?.onMessageTimedOut(chatMsgId) })
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
        onBotSettingsLoaded: @escaping ([String: String], [SessionLanguage]) -> Void = { _, _ in },
        onSessionTimeReceived: @escaping (Date) -> Void = { _ in },
        onTerminalClose: @escaping (String) -> Void = { _ in },
        // An untouched room to go back to instead of allocating a new one (see BlankRoomRegistry);
        // ignored when this device has no saved session for it.
        resumeBlankRoomId: String? = nil
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
        self.onSessionTimeReceived = onSessionTimeReceived
        self.onTerminalClose = onTerminalClose

        // Every open of the bot starts a fresh conversation rather than silently resuming
        // whatever room was last active - the previous conversation is still reachable from
        // the history drawer, this just controls what greets the user on open.
        let blankSession = resumeBlankRoomId.flatMap { sessionStore?.loadForRoom(botId: botId, roomId: $0) }
        await sessionMutex.lock()
        await establishSession(onConversationStarted: onConversationStarted, resumeRoomId: blankSession?.roomId, resumeSessionToken: blankSession?.sessionToken)
        await sessionMutex.unlock()
    }

    public func startNewSession(onConversationStarted: @escaping (String) async -> Bool = { _ in false }) async {
        await sessionMutex.lock()
        NSLog("[Chat360WS] Starting new session (user-initiated) - tearing down room=%@", roomId ?? "nil")
        await awaitPendingReplyBeforeTeardown()
        teardownForResession()
        await establishSession(onConversationStarted: onConversationStarted)
        await sessionMutex.unlock()
    }

    // Switches the live socket to `targetRoomId`. A room this device has a saved session token for is
    // resumed through the session endpoint. Any other room (one seen only in the rooms list - another
    // device, a reinstall, an older room) can't be resumed that way: the session endpoint ignores a
    // bare room id and allocates a different room. The web widget doesn't need a token to be in a room
    // either - its socket is just `ws/chat_updated/{ownerId}/{roomId}` - so that's what is used here:
    // the socket joins the same room and the flow starts again from the bot's opening node, which
    // begins a new session inside the room and keeps its history. Returns false only when there is no
    // owner id to connect with (no session has ever been established), so the caller can fall back.
    public func switchToRoom(targetRoomId: String, onConversationStarted: @escaping (String) async -> Bool = { _ in false }) async -> Bool {
        if let persisted = sessionStore?.loadForRoom(botId: botId, roomId: targetRoomId) {
            await sessionMutex.lock()
            NSLog("[Chat360WS] Switching to room=%@ (tearing down room=%@)", targetRoomId, roomId ?? "nil")
            await awaitPendingReplyBeforeTeardown()
            teardownForResession()
            await establishSession(onConversationStarted: onConversationStarted, resumeRoomId: targetRoomId, resumeSessionToken: persisted.sessionToken)
            await sessionMutex.unlock()
            return true
        }
        guard let owner = ownerId ?? sessionStore?.load(botId: botId)?.ownerId else { return false }
        await sessionMutex.lock()
        await joinRoomDirectly(owner: owner, targetRoomId: targetRoomId, onConversationStarted: onConversationStarted)
        await sessionMutex.unlock()
        return true
    }

    // Must run under `sessionMutex`.
    private func joinRoomDirectly(owner: String, targetRoomId: String, onConversationStarted: @escaping (String) async -> Bool) async {
        NSLog("[Chat360WS] Joining room=%@ directly, no saved session (tearing down room=%@)", targetRoomId, roomId ?? "nil")
        await awaitPendingReplyBeforeTeardown()
        teardownForResession()
        let myGeneration = _sessionGeneration.mutate { $0 += 1; return $0 }
        withState {
            ownerId = owner
            roomId = targetRoomId
            // No session id is known for a room joined this way; the same fallback establishSession uses.
            sessionId = targetRoomId
        }
        guard await onConversationStarted(targetRoomId), myGeneration == sessionGeneration else { return }
        await seedOpeningNode(generation: myGeneration)
        guard myGeneration == sessionGeneration else { return }
        withState {
            // The room already exists server-side, so its session_time can be asked for on open.
            sessionEverStarted = true
            guard myGeneration == sessionGeneration else { return }
            openSocket()
        }
    }

    /// Points `currentTargetId`/`lastBotNode` at the bot's opening node, without showing it: the next
    /// message sent goes out as the first message of a fresh session. Best-effort - on failure the
    /// position is left empty, like `loadConversationStarter`.
    private func seedOpeningNode(generation: Int) async {
        guard let items = try? await apiService.getFirstMessages(botId: botId) else { return }
        withState {
            guard generation == sessionGeneration else { return }
            for item in items {
                if case .botMessage(let node) = item.toIncomingEvent(), !isErrorNode(node) {
                    lastBotNode = node
                    currentTargetId = node.targetId ?? currentTargetId
                }
            }
        }
    }

    // Waits (briefly) for an in-flight bot reply to the last message sent on the room about to be
    // torn down to fully arrive, before teardownForResession() closes the socket out from under
    // it. Bounded by pendingReplyAwaitTimeoutMs so a slow/stuck bot can never block a room switch
    // or new chat indefinitely; a no-op when nothing is outstanding.
    private func awaitPendingReplyBeforeTeardown() async {
        guard hasPendingReply else { return }
        NSLog("[Chat360WS] Waiting up to %dms for in-flight bot reply before switching rooms (room=%@)", Self.pendingReplyAwaitTimeoutMs, roomId ?? "nil")
        let deadline = Date().addingTimeInterval(Double(Self.pendingReplyAwaitTimeoutMs) / 1000)
        while hasPendingReply && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        hasPendingReply = false
    }

    private func teardownForResession() {
        stateLock.lock()
        defer { stateLock.unlock() }
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
        hasPendingReply = false
        sessionEverStarted = false
        awaitingFirstBotReplySessionTime = false
        overrideNextSessionTimeWithNow = false
        awaitingImmediateSessionTimeCheck = false
        awaitingSessionTimeResponse = false
        pendingSessionResetOnNextBotMessage = false
    }

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func establishSession(onConversationStarted: @escaping (String) async -> Bool, resumeRoomId: String? = nil, resumeSessionToken: String? = nil) async {
        let myGeneration = _sessionGeneration.mutate { $0 += 1; return $0 }
        do {
            let host = hostComponent(of: baseUrl)
            let session = try await apiService.getSession(
                botId: botId,
                websiteUrl: host,
                currentUrl: "\(baseUrl)/web_bot/?h=\(botId)",
                roomId: resumeRoomId,
                sessionId: resumeSessionToken,
                meta: meta,
                dealerId: dealerId,
                empId: empId
            )
            guard myGeneration == sessionGeneration else {
                NSLog("[Chat360WS] Discarding superseded session establish (room=%@)", session.room_id)
                return
            }
            // Assigned together: openSocket() reads owner and room as a pair, and a reconnect timer
            // firing between two separate writes would connect to a mismatched owner/room.
            withState {
                ownerId = session.owner_id
                roomId = session.room_id
                // Falls back to room_id when the bot's own session init doesn't return a distinct
                // session_id (seen in practice - it's an optional field) - confirmed acceptable
                // rather than blocking the feedback API on a value that isn't always present.
                sessionId = session.session_id ?? session.room_id
                currentTargetId = session.targetId
            }
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
            guard myGeneration == sessionGeneration else { return }
            let hadHistory = await onConversationStarted(session.room_id)
            guard myGeneration == sessionGeneration else { return }
            if hadHistory {
                withState { pendingInitJumpTargetId = nil }
                // The replay above only updates the ViewModel's local cache/UI, never this
                // class's own currentTargetId/lastBotNode (those stay whatever teardownForResession
                // just reset them to) - and session.targetId can't be trusted to fill that gap on
                // a resumed room. Without this, a room whose current position is e.g. a
                // validation_error re-prompt (which itself carries no usable targetId) reconnects
                // with no known targetId at all, so the very next free-text reply goes out empty
                // and the flow can't route it. Folding through the room's recent history the same
                // way a live bot message would (see handleIncoming) recovers the last real
                // targetId before the user can send anything.
                await seedTargetContextFromHistory(roomId: session.room_id, generation: myGeneration)
            } else if await loadConversationStarter(generation: myGeneration) {
                withState { pendingInitJumpTargetId = nil }
            }
            // A resumed room's session already exists server-side - openSocket's onOpen can ask
            // for its session_time right away instead of waiting on a bot reply that reopening a
            // past conversation never provokes on its own. A genuinely new room has nothing to
            // ask about yet, so this stays false until its own first live reply sets it.
            withState {
                sessionEverStarted = hadHistory
                // Checked and acted on under one hold, so a newer establishSession can't slip in
                // between "still current" and opening the socket.
                guard myGeneration == sessionGeneration else { return }
                openSocket()
            }
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

    private func loadConversationStarter(generation: Int) async -> Bool {
        do {
            let items = try await apiService.getFirstMessages(botId: botId)
            // Awaited above: this session may have been superseded or disconnected meanwhile, and
            // its starter bubbles/target context must not land in whatever room is current now.
            guard generation == sessionGeneration else { return false }
            for item in items {
                if let data = try? encoder.encode(item), let text = String(data: data, encoding: .utf8) {
                    onRawIncoming(text)
                }
                let event = item.toIncomingEvent()
                if case .botMessage(let node) = event, !isErrorNode(node) {
                    withState {
                        lastBotNode = node
                        currentTargetId = node.targetId ?? currentTargetId
                    }
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
    private func seedTargetContextFromHistory(roomId: String, generation: Int) async {
        guard historyEnabled else { return }
        guard let response = try? await apiService.getHistory(roomId: roomId) else { return }
        // Applied atomically and only if this session is still the current one: it was fetched for
        // `roomId`, and writing it after a switch would give the new room the old room's position.
        withState {
            guard generation == sessionGeneration else { return }
            for item in response.history {
                if case .botMessage(let node) = item.toIncomingEvent(), !isErrorNode(node) {
                    lastBotNode = node
                    currentTargetId = node.targetId ?? currentTargetId
                }
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
        stateLock.lock()
        defer { stateLock.unlock() }
        guard ownerId != nil, roomId != nil else { return }
        NSLog("[Chat360WS] Manual reconnect requested (room=%@)", roomId ?? "nil")
        manuallyDisconnected = true
        reconnectManager.cancel()
        wsClient.close()
        openSocket()
    }

    private func openSocket() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let oId = ownerId, let rId = roomId else { return }
        manuallyDisconnected = false
        // A prior socket's own requestSessionTime() may still be in flight when that socket gets
        // torn down (e.g. the app is backgrounded right after the first bot reply, killing the
        // connection before its session_time round trip completes) - its response then simply
        // never arrives, leaving these correlation flags stuck set. Left uncleared, the *next*
        // socket's legitimate session_time response would wrongly be treated as the answer to
        // that dead request. Clearing them here means every new socket starts clean; onOpen below
        // sets whichever of these it actually needs.
        awaitingSessionTimeResponse = false
        overrideNextSessionTimeWithNow = false
        awaitingImmediateSessionTimeCheck = false
        let wsScheme = baseUrl.hasPrefix("https") ? "wss" : "ws"
        let host = hostComponent(of: baseUrl)
        let wsUrl = "\(wsScheme)://\(host)/ws/chat_updated/\(oId)/\(rId)"
        NSLog("[Chat360WS] Opening socket for owner=%@ room=%@", oId, rId)

        wsClient.connect(
            wsUrl: wsUrl,
            onOpen: { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                defer { self.stateLock.unlock() }
                NSLog("[Chat360WS] Connected (owner=%@ room=%@)", oId, rId)
                self.isSocketOpen = true
                self.reconnectPending = false
                self.heartbeat.start()
                self.reconnectManager.onConnected()
                self.onConnected()
                if self.sessionEverStarted {
                    // A resumed room, or a reconnect of a room already past its first reply - its
                    // session_time is safe to ask about right away. handleSessionTimeReceived
                    // decides whether the answer is fresh enough to show immediately or stale
                    // enough to hold back - see awaitingImmediateSessionTimeCheck.
                    self.awaitingImmediateSessionTimeCheck = true
                    self.requestSessionTime()
                } else {
                    // A genuinely new room has no session_time to ask about yet - the timer must
                    // stay hidden/not-running until the user sends something new and a bot reply
                    // actually arrives live on this connection (see the botMessage case below,
                    // which fires the request once this is consumed).
                    self.awaitingFirstBotReplySessionTime = true
                }
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
        stateLock.lock()
        defer { stateLock.unlock() }
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
        stateLock.lock()
        defer { stateLock.unlock() }
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
        stateLock.lock()
        defer { stateLock.unlock() }
        // The response shape for this one isn't part of the normal message protocol
        // (`RawSocketEnvelope` only decodes the fields it knows about, silently dropping anything
        // else), so it's parsed separately here rather than added as a proper `IncomingSocketEvent`.
        if raw.contains("session_time_hyundai") {
            NSLog("[Chat360WS] Session time response: %@", raw)
            if let data = raw.data(using: .utf8),
               let response = try? decoder.decode(SessionTimeResponse.self, from: data),
               let createdAtRaw = response.session?.created_at,
               let createdAt = Self.parseSessionTimestamp(createdAtRaw) {
                handleSessionTimeReceived(createdAt)
            }
            return
        }
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
            // Only a complete reply clears the pending-reply gate - a streaming (chatgpt_message)
            // answer must keep the socket open across every chunk, not just its first one, so
            // awaitPendingReplyBeforeTeardown waits for streamEnded.
            if node.streamId == nil || node.streamEnded {
                hasPendingReply = false
            }
            if awaitingFirstBotReplySessionTime {
                awaitingFirstBotReplySessionTime = false
                sessionEverStarted = true
                overrideNextSessionTimeWithNow = true
                NSLog("[Chat360WS] First live bot reply on this connection - requesting session time, countdown will start at 59:59 (room=%@)", roomId ?? "nil")
                requestSessionTime()
            }
            if pendingSessionResetOnNextBotMessage {
                pendingSessionResetOnNextBotMessage = false
                NSLog("[Chat360WS] Applying deferred session time reset on this bot reply - countdown restarts at 59:59 (room=%@)", roomId ?? "nil")
                onSessionTimeReceived(Date())
            }
            handleWindowEventNode(node.content)
            if let endUrlMessage = node.endUrlMessage { onOpenUrl(endUrlMessage) }
            if node.endSessionRequested {
                disconnect()
            } else if let autoAdvanceTargetId = node.autoAdvanceTargetIdOrNull() {
                // A passive node (plain text, link card, download-media notice, ...) doesn't
                // wait on the user - the flow stays blocked server-side until the client
                // re-submits this node's own targetId as a system jump, same as the web
                // widget's auto-advance effect. Without this, a chain of several back-to-back
                // passive messages (e.g. right after a WINDOW_EVENT response) renders only the
                // first bubble and silently stalls.
                sendSystemJump(targetId: autoAdvanceTargetId)
            }
        case .ack(let chatMsgId):
            ackTracker.acknowledge(chatMsgId: chatMsgId)
        case .echoedUserMessage(let chatMsgId, _, _):
            ackTracker.acknowledge(chatMsgId: chatMsgId)
        case .closeConnection(let suppress, let terminalMessage):
            if suppress { suppressReconnect = true }
            if let terminalMessage { handleTerminalClose(message: terminalMessage) }
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

    // Requests the Hyundai-specific server-tracked session duration for the current room.
    // Standalone frame, not ack-tracked (same pattern as sendSystemJump/the heartbeat ping).
    private func requestSessionTime() {
        awaitingSessionTimeResponse = true
        guard let rId = roomId, let data = try? encoder.encode(SessionTimeRequest(room_id: rId)), let text = String(data: data, encoding: .utf8) else { return }
        wsClient.send(text)
    }

    // Decides whether an incoming session_time_hyundai reply is trustworthy enough to show right
    // away, or must be held back until the bot's next reply confirms the flow is actually still
    // alive - see awaitingImmediateSessionTimeCheck/pendingSessionResetOnNextBotMessage's own docs.
    private func handleSessionTimeReceived(_ createdAt: Date) {
        guard awaitingSessionTimeResponse else {
            // Unprompted - the backend pushes one of these on its own when the current session's
            // hour window lapses and rolls over to a fresh one. Held back until the bot's next
            // reply actually arrives instead of snapping the countdown to 59:59 the instant this
            // frame lands with no bot activity behind it.
            NSLog("[Chat360WS] Unsolicited session time reset received - deferring to next bot reply (room=%@)", roomId ?? "nil")
            pendingSessionResetOnNextBotMessage = true
            return
        }
        awaitingSessionTimeResponse = false
        if overrideNextSessionTimeWithNow {
            overrideNextSessionTimeWithNow = false
            onSessionTimeReceived(Date())
            return
        }
        if awaitingImmediateSessionTimeCheck {
            awaitingImmediateSessionTimeCheck = false
            let elapsedSeconds = Date().timeIntervalSince(createdAt)
            if elapsedSeconds < Self.freshlyCreatedSessionWindowSeconds {
                // A created_at this close to "now" means the backend just minted it for this very
                // query (an expired/stale session gets silently renewed rather than returning its
                // true old start time) - not a real value worth trusting yet.
                NSLog("[Chat360WS] Resumed session's created_at is only %.0fs old - deferring to next bot reply (room=%@)", elapsedSeconds, roomId ?? "nil")
                pendingSessionResetOnNextBotMessage = true
                return
            }
            // Genuinely old enough to trust - show the real remaining time immediately.
        }
        onSessionTimeReceived(createdAt)
    }

    /// Non-WindowEvent nodes leave the gate untouched: the host's response to a window event is
    /// asynchronous (it waits on user interaction with a native dialog/WebView), so an unrelated
    /// bot frame - a typing indicator, a session-time nudge, a concurrent flow node - can easily
    /// land in between. Previously that frame flipped `receiving` back to false, so the host's
    /// eventual sendEventToBot() call silently dropped the event, stalling the flow forever
    /// ("no next message after a window event"). Only a *new* WindowEvent node should change who
    /// is allowed to receive, since that's the only signal the flow has actually moved past the
    /// one currently waiting on a host response.
    private func handleWindowEventNode(_ content: BotContent) {
        guard case .windowEvent(let windowEvent) = content else { return }
        WindowEventBridge.shared.setReceiving(windowEvent.shouldReceive)
        if windowEvent.shouldSend {
            let response = WindowEventBridge.shared.dispatchToHost(handleWindowEvent: Chat360Bot.shared.handleWindowEvents, sendData: windowEvent.sendData)
            if !response.isEmpty { WindowEventBridge.shared.sendToActiveSession(response) }
        }
    }

    /// The inbound half: an event handed to the active session becomes a system-jump frame
    /// carrying it as `variable_values` - the same `user: "bot"` / `data.target_id` / `curr_id` /
    /// `variable_values` shape the web widget's WindowEvent component sends (see jumpToEleBot /
    /// sendSocketMessage there), not a regular end_user chat message. The flow engine's
    /// window-event-advance handling is keyed on that shape: an end_user-authored frame (what
    /// this used to send, reusing OutgoingMessage/variables/nodeType) looks like an ordinary
    /// reply and is never recognized as "advance past this window-event node," so the bot
    /// silently acks it and never emits a next message.
    private func sendWindowEvent(_ event: [String: String]) {
        guard let targetId = lastBotNode?.targetId ?? currentTargetId else { return }
        sendSystemJump(targetId: targetId, variableValues: event)
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

    private func sendSystemJump(targetId: String, variableValues: [String: String]? = nil) {
        let jump = SystemJumpMessage(
            data: SystemJumpMessage.JumpData(target_id: targetId, currentUrl: "\(baseUrl)/web_bot/?h=\(botId)"),
            bot_id: botId,
            curr_id: lastBotNode?.nodeId,
            room_id: roomId,
            variable_values: variableValues
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
        // Marks a bot reply as outstanding for this room - see awaitPendingReplyBeforeTeardown,
        // which keeps the socket open long enough for it to actually arrive if the user switches
        // rooms/starts a new chat before it does.
        hasPendingReply = true
        guard let data = try? encoder.encode(outgoing), let payload = String(data: data, encoding: .utf8) else { return outgoing.chat_msg_id }
        if !wsClient.send(payload) { ensureReconnecting() }
        ackTracker.trackSend(chatMsgId: outgoing.chat_msg_id) { [weak self] in
            guard let self else { return }
            if !self.wsClient.send(payload) { self.ensureReconnecting() }
        }
        return outgoing.chat_msg_id
    }

    public func disconnect() {
        stateLock.lock()
        defer { stateLock.unlock() }
        NSLog("[Chat360WS] Disconnecting (manual, final) - room=%@", roomId ?? "nil")
        // An establishSession still awaiting the network would otherwise finish later and
        // openSocket() a live socket for a repository nobody is listening to any more (openSocket
        // even clears `manuallyDisconnected`). Bumping the generation makes it discard itself.
        _sessionGeneration.mutate { $0 += 1 }
        manuallyDisconnected = true
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()
        hasPendingReply = false
        WindowEventBridge.shared.unregisterSession()
    }

    // Dealer/SE deactivated from the dashboard, or maintenance mode activated - both server-side
    // states end this session for good, but unlike `disconnect()` they're not the user's own
    // choice to leave, so this stays recoverable: it stops the heartbeat/reconnect backoff and
    // closes the socket, same as `disconnect()`, but deliberately skips
    // `WindowEventBridge.shared.unregisterSession()` and leaves ownerId/roomId/sessionId intact,
    // so `reconnectNow()` -> `openSocket()` (foreground, or a manual retry) can still open a
    // fresh socket on the same session later.
    private func handleTerminalClose(message: String) {
        NSLog("[Chat360WS] Terminal close_connection received (room=%@): %@", roomId ?? "nil", message)
        manuallyDisconnected = true
        heartbeat.stop()
        reconnectManager.cancel()
        ackTracker.cancelAll()
        wsClient.close()
        hasPendingReply = false
        onTerminalClose(message)
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func hostComponent(of url: String) -> String {
        guard let range = url.range(of: "://") else { return url }
        return String(url[range.upperBound...])
    }

    // `created_at` comes back with no timezone designator (e.g. "2026-08-25T07:56:31.699927"),
    // but the value itself is already UTC - confirmed against the same payload's own
    // `@current_datetime`/`@room_updated` variables (which are IST) landing within a second of
    // this value once converted to UTC, for a session that had just been created. An earlier
    // version of this treated the unmarked string as IST and shifted it back 5:30, which placed
    // a freshly-created session's `expiresAt` hours in the past - the countdown UI hides itself
    // once remaining time goes negative, so that showed no timer at all instead of a wrong one.
    // Fractional seconds are dropped rather than parsed - they're µs-precision and irrelevant to
    // a minute-granularity session countdown.
    private static func parseSessionTimestamp(_ raw: String) -> Date? {
        let wholeSeconds = raw.split(separator: ".").first.map(String.init) ?? raw
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: wholeSeconds)
    }
}

private struct SessionTimeResponse: Codable {
    struct Session: Codable {
        let room_id: String?
        let session_id: String?
        let admin_uuid: String?
        let created_at: String?
    }
    let data_type: String?
    let session: Session?
    let found: Bool?
}

public enum Chat360RepositoryError: Error {
    case notConnected
    case uploadFailed
}

// A minimal FIFO async lock - serializes ChatRepository's connect()/startNewSession()/
// switchToRoom() end to end (see sessionMutex's own doc). Not reentrant: a second lock() call
// from the same logical caller before unlock() would deadlock, but nothing in this file ever
// does that.
@available(iOS 13.0, *)
private actor AsyncMutex {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
