import Foundation

@available(iOS 13.0, *)
public struct Attachment: Equatable {
    public var fileName: String
    public var progress: Int = 0
    public var uploaded: Bool = false
    public var failed: Bool = false

    public init(fileName: String, progress: Int = 0, uploaded: Bool = false, failed: Bool = false) {
        self.fileName = fileName
        self.progress = progress
        self.uploaded = uploaded
        self.failed = failed
    }
}

@available(iOS 13.0, *)
public struct FormState: Equatable {
    public var values: [Int: String] = [:]
    public var submitted: Bool = false
    public var attemptedSubmit: Bool = false
    public var fileNames: [Int: String] = [:]
    public var uploadingFields: Set<Int> = []

    public init(values: [Int: String] = [:], submitted: Bool = false, attemptedSubmit: Bool = false, fileNames: [Int: String] = [:], uploadingFields: Set<Int> = []) {
        self.values = values
        self.submitted = submitted
        self.attemptedSubmit = attemptedSubmit
        self.fileNames = fileNames
        self.uploadingFields = uploadingFields
    }
}

@available(iOS 13.0, *)
public struct PromptState: Equatable {
    public var value: String = ""
    public var secondaryValue: String = ""
    public var submitted: Bool = false

    public init(value: String = "", secondaryValue: String = "", submitted: Bool = false) {
        self.value = value
        self.secondaryValue = secondaryValue
        self.submitted = submitted
    }
}

@available(iOS 13.0, *)
public struct VoiceDraftState: Equatable {
    public var filePath: String
    public var amplitudes: [Int]
    public var durationMs: Int64
    public var uploading: Bool = false
    public var uploadProgress: Int = 0
    public var error: String?

    public init(filePath: String, amplitudes: [Int], durationMs: Int64, uploading: Bool = false, uploadProgress: Int = 0, error: String? = nil) {
        self.filePath = filePath
        self.amplitudes = amplitudes
        self.durationMs = durationMs
        self.uploading = uploading
        self.uploadProgress = uploadProgress
        self.error = error
    }
}

@available(iOS 13.0, *)
public struct VoiceMessageInfo: Equatable {
    public var localFilePath: String?
    public var remoteUrl: String?
    public var amplitudes: [Int]
    public var durationMs: Int64

    public init(localFilePath: String?, remoteUrl: String?, amplitudes: [Int], durationMs: Int64) {
        self.localFilePath = localFilePath
        self.remoteUrl = remoteUrl
        self.amplitudes = amplitudes
        self.durationMs = durationMs
    }
}

@available(iOS 13.0, *)
public func formatMessageTime(_ timestampMs: Int64? = nil) -> String {
    let date = timestampMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale.current
    return formatter.string(from: date)
}

@available(iOS 13.0, *)
public struct ChatMessage: Equatable, Identifiable {
    public var id: String = UUID().uuidString
    public var chatMsgId: String?
    public var text: String
    public var fromUser: Bool
    public var failed: Bool = false
    public var timeText: String = formatMessageTime()
    public var content: BotContent = .plainText
    public var repliesEnabled: Bool = true
    public var selectedReplyIndex: Int?
    public var attachment: Attachment?
    public var formState: FormState?
    public var promptState: PromptState?
    public var checkedIndices: Set<Int> = []
    public var streamId: String?
    public var author: BotNode.MessageAuthor = .bot
    public var voiceMessage: VoiceMessageInfo?
    // Unlike `id` (a fresh random UUID every time this struct is built, including on replay),
    // this comes straight from the server and round-trips identically through both live
    // delivery and cache/history replay - it's the only thing that reliably re-identifies "the
    // same message" across an app restart, so it's what reaction persistence keys on.
    public var timestampMs: Int64?
    // The bot flow node this message was generated from - reported to the third-party-tasks
    // feedback API as `message_id` on like/dislike, per the backend contract. Same caveat as
    // any other field sourced from the flow graph rather than a per-instance id: if the same
    // node fires more than once in a conversation, both messages share this value.
    public var nodeId: String?

    public init(
        id: String = UUID().uuidString, chatMsgId: String? = nil, text: String, fromUser: Bool, failed: Bool = false,
        timeText: String = formatMessageTime(), content: BotContent = .plainText, repliesEnabled: Bool = true,
        selectedReplyIndex: Int? = nil, attachment: Attachment? = nil, formState: FormState? = nil,
        promptState: PromptState? = nil, checkedIndices: Set<Int> = [], streamId: String? = nil,
        author: BotNode.MessageAuthor = .bot, voiceMessage: VoiceMessageInfo? = nil, timestampMs: Int64? = nil,
        nodeId: String? = nil
    ) {
        self.id = id
        self.chatMsgId = chatMsgId
        self.text = text
        self.fromUser = fromUser
        self.failed = failed
        self.timeText = timeText
        self.content = content
        self.repliesEnabled = repliesEnabled
        self.selectedReplyIndex = selectedReplyIndex
        self.attachment = attachment
        self.formState = formState
        self.promptState = promptState
        self.checkedIndices = checkedIndices
        self.streamId = streamId
        self.author = author
        self.voiceMessage = voiceMessage
        self.timestampMs = timestampMs
        self.nodeId = nodeId
    }
}

@available(iOS 13.0, *)
public struct ChatUiState: Equatable {
    public var messages: [ChatMessage] = []
    public var isConnected: Bool = false
    public var isAgentTyping: Bool = false
    public var isSlowConnection: Bool = false
    public var inputText: String = ""
    public var error: String?
    public var colorOverrides: Chat360ColorOverrides?
    public var logoOverride: Chat360Logo?
    public var botTitleOverride: String?
    public var pendingUrlToOpen: String?
    public var isLiveChat: Bool = false
    public var assignedAgent: AssignedAgent?
    public var voiceDraft: VoiceDraftState?
    public var feedbackConfig: FeedbackConfig?
    public var showFeedbackPrompt: Bool = false
    public var isArchived: Bool = false
    public var hasMoreHistory: Bool = false
    public var isLoadingMoreHistory: Bool = false
    public var isHistoryUnavailable: Bool = false
    public var activeConversationId: String?
    public var pendingFeedbackMessageId: String?
    public var pendingFeedbackTimestampMs: Int64?
    public var messageReactions: [Int64: Bool] = [:]
    // Purely a client-side display, not tied to any real backend session lifetime. Starts on
    // the conversation's first user message, keeps counting down regardless of further
    // activity, and only restarts (from a fresh hour) once it's actually expired and the user
    // sends another message - never reset by messages sent while still running.
    public var sessionTimerExpiresAt: Date?

    public init() {}

    public static func == (lhs: ChatUiState, rhs: ChatUiState) -> Bool {
        lhs.messages == rhs.messages &&
            lhs.isConnected == rhs.isConnected &&
            lhs.isAgentTyping == rhs.isAgentTyping &&
            lhs.isSlowConnection == rhs.isSlowConnection &&
            lhs.inputText == rhs.inputText &&
            lhs.error == rhs.error &&
            lhs.logoOverride == rhs.logoOverride &&
            lhs.botTitleOverride == rhs.botTitleOverride &&
            lhs.pendingUrlToOpen == rhs.pendingUrlToOpen &&
            lhs.isLiveChat == rhs.isLiveChat &&
            lhs.assignedAgent == rhs.assignedAgent &&
            lhs.voiceDraft == rhs.voiceDraft &&
            lhs.showFeedbackPrompt == rhs.showFeedbackPrompt &&
            lhs.isArchived == rhs.isArchived &&
            lhs.hasMoreHistory == rhs.hasMoreHistory &&
            lhs.isLoadingMoreHistory == rhs.isLoadingMoreHistory &&
            lhs.isHistoryUnavailable == rhs.isHistoryUnavailable &&
            lhs.activeConversationId == rhs.activeConversationId &&
            lhs.pendingFeedbackMessageId == rhs.pendingFeedbackMessageId &&
            lhs.pendingFeedbackTimestampMs == rhs.pendingFeedbackTimestampMs &&
            lhs.messageReactions == rhs.messageReactions &&
            lhs.sessionTimerExpiresAt == rhs.sessionTimerExpiresAt
    }
}
