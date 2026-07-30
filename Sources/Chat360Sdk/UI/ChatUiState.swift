import Foundation

/// Local (not server-echoed) state for a user-initiated file upload, keyed by `ChatMessage.id`.
struct Attachment: Equatable {
    var fileName: String
    var progress: Int = 0
    var uploaded: Bool = false
    var failed: Bool = false
}

/// Local draft state for a `BotContent.form` message: field index -> typed value, plus submitted
/// flag. `attemptedSubmit` gates inline error text - errors only show after the user has tried to
/// submit once, not while a field is merely empty/untouched.
struct FormState: Equatable {
    var values: [Int: String] = [:]
    var submitted: Bool = false
    var attemptedSubmit: Bool = false
    /// MEDIA fields only: field index -> the picked file's original name (values[index] holds the uploaded URL).
    var fileNames: [Int: String] = [:]
    /// MEDIA fields only: field indices with an upload currently in flight.
    var uploadingFields: Set<Int> = []
}

/// Local draft state for EmailPrompt (uses `value` only) / PhonePrompt (country code + national number).
struct PromptState: Equatable {
    var value: String = ""
    var secondaryValue: String = ""
    var submitted: Bool = false
}

/// A recorded-but-not-yet-sent voice note. `amplitudes` are the raw samples captured while
/// recording, reused to draw the static waveform in both the review chip and (once sent) the sent
/// bubble.
struct VoiceDraftState: Equatable {
    var filePath: String
    var amplitudes: [Int]
    var durationMs: Int64
    var uploading: Bool = false
    var uploadProgress: Int = 0
    var error: String?
}

/// A sent (or sending) voice message bubble - `localFilePath` answers playback instantly, before/without `remoteUrl`.
struct VoiceMessageInfo: Equatable {
    var localFilePath: String?
    var remoteUrl: String?
    var amplitudes: [Int]
    var durationMs: Int64
}

struct ChatMessage: Equatable, Identifiable {
    var id: String = UUID().uuidString
    var chatMsgId: String?
    var text: String
    var fromUser: Bool
    var failed: Bool = false
    var timeText: String = ChatMessage.formattedNow()
    var content: BotContent = .plainText
    var repliesEnabled: Bool = true
    var selectedReplyIndex: Int?
    var attachment: Attachment?
    var formState: FormState?
    var promptState: PromptState?
    /// Which MultiOption indices are currently checked - unlike selectedReplyIndex, more than one.
    var checkedIndices: Set<Int> = []
    /// Set only for a chatgpt_message streaming bubble - later chunks sharing this id merge into it.
    var streamId: String?
    /// BOT vs AGENT-authored (an admin/operator message) - drives the row's name/avatar swap.
    var author: BotNode.MessageAuthor = .bot
    /// Set only for a sent VOICE_MESSAGE - mutually exclusive with `attachment`/`text` rendering.
    var voiceMessage: VoiceMessageInfo?

    private static func formattedNow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

struct ChatUiState: Equatable {
    var messages: [ChatMessage] = []
    var isConnected: Bool = false
    var isAgentTyping: Bool = false
    var isSlowConnection: Bool = false
    var inputText: String = ""
    var error: String?
    /// Server-driven "other values fetched from the API" layer, applied on top of the chosen theme preset.
    var colorOverrides: Chat360ColorOverrides?
    var logoOverride: Chat360Logo?
    var botTitleOverride: String?
    /// An END node's urlMessage, to be opened externally once by the UI then cleared.
    var pendingUrlToOpen: String?
    /// True while the session is being handled by a human agent rather than the bot flow - set on
    /// any admin/operator-authored message (not just an AGENT_TRANSFER/TEAM_TRANSFER notice), and
    /// cleared on the next bot-authored message or an `update_status` end signal.
    var isLiveChat: Bool = false
    /// The human agent currently assigned, from a `highlight` node - re-updatable for agent-to-agent transfer.
    var assignedAgent: AssignedAgent?
    /// A stopped-but-unsent recording awaiting review/send/cancel - swaps ChatInputBar out for VoiceRecorderBar.
    var voiceDraft: VoiceDraftState?
    /// The bot-owner-authored post-chat survey definition, from the appearance API's json_info.
    var feedbackConfig: FeedbackConfig?
    /// True once `shouldAskFeedback` held the session open pending a submitted (or skipped) survey.
    var showFeedbackPrompt: Bool = false
    /// A `chat_inactivity_message` with `auto_archival` - the session is closing for inactivity,
    /// so the input bar disables.
    var isArchived: Bool = false
}
