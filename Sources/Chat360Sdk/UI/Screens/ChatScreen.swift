import SwiftUI
import UIKit

/// Top-level chat screen: owns layout only. Every visual piece (header, splash, message rows,
/// input bar) lives in `UI/Components/` so this file stays readable as content types grow.
///
/// Colors/branding are resolved in two layers: `.chat360Theme(...)` (set once, outside this
/// screen) picks the base preset/custom look, and this screen re-provides both environment values
/// with the bot's server-side appearance config (fetched async, may arrive after first render)
/// layered on top.
struct ChatScreen: View {
    @ObservedObject var viewModel: ChatViewModel
    var appearanceOverride: Binding<ColorScheme?> = .constant(nil)
    /// True when the host app configured its own full `.custom` color palette (e.g. a client's
    /// own brand, like the demo app's Hyundai theme) - in that case the bot's server-side
    /// appearance colors never apply at all, not even before the user has touched the
    /// Light/Dark toggle. Without this, a `.custom`-branded bot whose own appearance API also
    /// happens to return colors would flash the wrong (server) colors on first render and only
    /// "stabilize" into the correct custom palette once the user manually picked Light or Dark -
    /// since that's the only thing that made `effectiveColors` below stop applying overrides.
    var suppressServerColorOverrides: Bool = false

    @Environment(\.chat360Colors) private var baseColors
    @Environment(\.chat360Branding) private var baseBranding
    @Environment(\.openURL) private var openURL

    @StateObject private var voiceRecorder = VoiceRecorderController()
    @StateObject private var voicePreviewPlayback = VoicePlaybackController()
    @StateObject private var speechToText = SpeechToTextController()
    @State private var showEmojiPicker = false
    @State private var showAttachmentPicker = false
    @State private var showCameraPicker = false
    @State private var mediaFieldPickerTarget: FormFieldTarget?
    @State private var isDrawerOpen = false

    /// The bot's server-side appearance colors normally apply on top of the theme (see the type
    /// doc above) - but once the user has explicitly picked Light/Dark from the drawer, that
    /// choice wins completely instead, server overrides included. Otherwise the toggle would look
    /// broken: the server colors would keep winning for the fields they set (background, bubbles,
    /// accent - the most visually obvious ones) no matter what the user picked.
    private var effectiveColors: Chat360Colors {
        guard !suppressServerColorOverrides else { return baseColors }
        guard appearanceOverride.wrappedValue == nil else { return baseColors }
        return baseColors.applyingOverrides(viewModel.uiState.colorOverrides)
    }

    private var effectiveBranding: Chat360Branding {
        var branding = baseBranding
        if let title = viewModel.uiState.botTitleOverride { branding.botTitle = title }
        if let logo = viewModel.uiState.logoOverride { branding.logo = logo }
        return branding
    }

    /// The most-recent message, while it's a WELCOME_SCREEN, renders fixed above the scroll list
    /// instead of inside it: it stops being pinned automatically once anything else arrives after it.
    private var pinnedWelcomeMessage: ChatMessage? {
        guard let last = viewModel.uiState.messages.last, !last.fromUser else { return nil }
        if case .welcomeScreen = last.content { return last }
        return nil
    }

    private var listMessages: [ChatMessage] {
        pinnedWelcomeMessage != nil ? Array(viewModel.uiState.messages.dropLast()) : viewModel.uiState.messages
    }

    var body: some View {
        let state = viewModel.uiState

        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                // Paints the system status bar's background to match `colors.statusBar` - a
                // zero-height colored view whose `.ignoresSafeArea(edges: .top)` extends its fill
                // backward behind the status bar without taking any layout space itself. iOS has
                // no direct API to set the status bar color, so this paints the same visual
                // result instead.
                effectiveColors.statusBar
                    .frame(height: 0)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .top)

                HeaderBar(
                    connected: state.isConnected,
                    assignedAgent: state.assignedAgent,
                    shortcuts: viewModel.shortcuts,
                    onMenuTap: { withAnimation { isDrawerOpen = true } },
                    onNewSession: { viewModel.startNewChat() },
                    onShortcutSelected: { viewModel.selectShortcut($0) },
                    onReconnectTap: { viewModel.reconnectNow() }
                )

                if let error = state.error {
                    StatusBanner(text: "Error: \(error)", emphasized: true)
                }
                if state.isSlowConnection {
                    StatusBanner(text: "Slow connection…", emphasized: false)
                }

                if let pinned = pinnedWelcomeMessage {
                    botMessageItem(pinned, isLiveChat: state.isLiveChat, assignedAgent: state.assignedAgent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                if state.messages.isEmpty {
                    WelcomeSplash().frame(maxHeight: .infinity)
                } else if !listMessages.isEmpty || state.isAgentTyping {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                // Scroll-to-top pagination trigger - invisible, sits above the
                                // oldest loaded message so it comes into view exactly when the
                                // user scrolls all the way up.
                                if state.hasMoreHistory {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear { viewModel.loadMoreHistory() }
                                }
                                if state.isLoadingMoreHistory {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                ForEach(listMessages) { message in
                                    Group {
                                        if message.fromUser {
                                            UserMessageRow(message: message)
                                        } else {
                                            botMessageItem(message, isLiveChat: state.isLiveChat, assignedAgent: state.assignedAgent)
                                        }
                                    }
                                    .id(message.id)
                                }
                                if state.isAgentTyping {
                                    TypingIndicatorRow().id("typing-indicator")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: state.messages.count) { _ in scrollToBottom(proxy: proxy, state: state) }
                        .onChange(of: state.isAgentTyping) { _ in scrollToBottom(proxy: proxy, state: state) }
                    }
                } else {
                    Spacer()
                }

                bottomBar(state: state)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(effectiveColors.background)

            if isDrawerOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { isDrawerOpen = false } }
                    .transition(.opacity)

                ChatDrawer(
                    conversations: viewModel.conversations,
                    activeConversationId: viewModel.activeConversationId,
                    languages: viewModel.languages,
                    onNewChat: {
                        withAnimation { isDrawerOpen = false }
                        viewModel.startNewChat()
                    },
                    onConversationSelected: { id in
                        withAnimation { isDrawerOpen = false }
                        viewModel.openConversation(id)
                    },
                    onConversationRenamed: { id, title in viewModel.renameConversation(id, title: title) },
                    onConversationDeleted: { id in viewModel.deleteConversation(id) },
                    onLanguageSelected: { language in viewModel.switchLanguage(language) },
                    appearanceOverride: appearanceOverride
                )
                .transition(.move(edge: .leading))
            }
        }
        .environment(\.chat360Colors, effectiveColors)
        .environment(\.chat360Branding, effectiveBranding)
        .onChange(of: state.pendingUrlToOpen) { pending in
            guard let pending, let url = URL(string: pending) else { return }
            openURL(url)
            viewModel.clearPendingUrl()
        }
        .onChange(of: speechToText.transcript) { transcript in
            if speechToText.isListening { viewModel.onInputChange(transcript) }
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentDocumentPicker { payload in
                viewModel.sendFile(bytes: payload.bytes, fileName: payload.fileName, mimeType: payload.mimeType)
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            AttachmentCameraCapture { payload in
                viewModel.sendFile(bytes: payload.bytes, fileName: payload.fileName, mimeType: payload.mimeType)
            }
        }
        .sheet(item: $mediaFieldPickerTarget) { target in
            AttachmentDocumentPicker { payload in
                viewModel.uploadFormField(messageId: target.messageId, fieldIndex: target.fieldIndex, bytes: payload.bytes, fileName: payload.fileName, mimeType: payload.mimeType)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.showFeedbackPrompt && state.feedbackConfig != nil },
            set: { if !$0 { viewModel.dismissFeedbackPrompt() } }
        )) {
            if let feedbackConfig = state.feedbackConfig {
                FeedbackFormDialog(
                    feedbackConfig: feedbackConfig,
                    onSubmit: { rating, feedbackText in viewModel.submitFeedback(rating: rating, feedbackText: feedbackText) },
                    onDismiss: { viewModel.dismissFeedbackPrompt() }
                )
            }
        }
    }

    @ViewBuilder
    private func bottomBar(state: ChatUiState) -> some View {
        let voiceDraft = state.voiceDraft
        if state.isArchived {
            StatusBanner(text: "This conversation has been archived due to inactivity.", emphasized: false)
        } else if voiceRecorder.isRecording || voiceDraft != nil {
            VoiceRecorderBar(
                isRecording: voiceRecorder.isRecording,
                liveAmplitudes: voiceRecorder.amplitudes,
                elapsedMs: voiceRecorder.elapsedMs,
                onStopRecording: {
                    if let recording = voiceRecorder.stop() {
                        viewModel.onVoiceRecordingCaptured(filePath: recording.fileURL.path, amplitudes: recording.amplitudes, durationMs: recording.durationMs)
                    }
                },
                onCancelRecording: { voiceRecorder.cancel() },
                draftAmplitudes: voiceDraft?.amplitudes ?? [],
                draftDurationMs: voiceDraft?.durationMs ?? 0,
                draftUploading: voiceDraft?.uploading ?? false,
                draftUploadProgress: voiceDraft?.uploadProgress ?? 0,
                draftError: voiceDraft?.error,
                playbackController: voicePreviewPlayback,
                draftLocalFilePath: voiceDraft?.filePath,
                onSendDraft: { viewModel.sendVoiceDraft() },
                onCancelDraft: {
                    voicePreviewPlayback.pause()
                    viewModel.cancelVoiceDraft()
                }
            )
        } else if speechToText.isListening {
            SpeechToTextBar(isListening: true, error: speechToText.error, onStop: { speechToText.stop() })
        } else {
            VStack(spacing: 0) {
                if showEmojiPicker {
                    EmojiPickerPanel(onEmojiSelected: { emoji in viewModel.onInputChange(state.inputText + emoji) })
                }
                ChatInputBar(
                    value: Binding(get: { state.inputText }, set: { viewModel.onInputChange($0) }),
                    onSend: { viewModel.sendMessage() },
                    onAttachmentClick: { showAttachmentPicker = true },
                    onMicClick: { voiceRecorder.requestStart() },
                    showDictationIcon: speechToText.isSupported(),
                    onDictateClick: { speechToText.requestStart() },
                    onEmojiClick: { showEmojiPicker.toggle() }
                )
            }
        }
    }

    private func botMessageItem(_ message: ChatMessage, isLiveChat: Bool, assignedAgent: AssignedAgent?) -> some View {
        BotMessageRow(
            message: message,
            actions: BotContentActions(
                onQuickReply: { option in viewModel.selectQuickReply(messageId: message.id, option: option) },
                onAttachmentClick: { showAttachmentPicker = true },
                onCameraClick: { showCameraPicker = true },
                onRatingSelected: { value in viewModel.selectRating(messageId: message.id, value: value) },
                onFormFieldChange: { index, value in viewModel.updateFormField(messageId: message.id, fieldIndex: index, value: value) },
                onMediaFieldPicked: { index, bytes, fileName, mimeType in
                    viewModel.uploadFormField(messageId: message.id, fieldIndex: index, bytes: bytes, fileName: fileName, mimeType: mimeType)
                },
                onPickMediaField: { index in mediaFieldPickerTarget = FormFieldTarget(messageId: message.id, fieldIndex: index) },
                onFormSubmit: { viewModel.submitForm(messageId: message.id) },
                onPromptValueChange: { primary, secondary in viewModel.updatePromptValue(messageId: message.id, primary: primary, secondary: secondary) },
                onEmailSubmit: { viewModel.submitEmail(messageId: message.id) },
                onPhoneSubmit: { viewModel.submitPhone(messageId: message.id) },
                onAutoSuggestionSelected: { index, text in viewModel.selectAutoSuggestion(messageId: message.id, index: index, text: text) },
                onDateSelected: { date in viewModel.selectDate(messageId: message.id, formattedDate: date) },
                onTimeSubmit: { time in viewModel.submitTime(messageId: message.id, formattedTime: time) },
                onCheckboxToggle: { index in viewModel.toggleCheckbox(messageId: message.id, index: index) },
                onCheckboxSubmit: { viewModel.submitCheckboxes(messageId: message.id) },
                onImageButtonClick: { card, button in
                    let submitType: String = { if case .imageButtons(let content) = message.content { return content.submitType }; return "BUTTON" }()
                    viewModel.selectImageButton(messageId: message.id, card: card, button: button, submitType: submitType)
                },
                onTextCarouselTap: { text, index, targetId in viewModel.selectTextCarouselReply(messageId: message.id, text: text, clickedIndex: index, targetId: targetId) },
                onWelcomeCardSelected: { card, index in viewModel.selectWelcomeCard(messageId: message.id, card: card, index: index) },
                onIframeAdvance: { targetId in viewModel.advanceFromIframe(targetId: targetId) },
                onCopy: { UIPasteboard.general.string = message.text },
                onRegenerate: { viewModel.regenerate(messageId: message.id) },
                onLike: { viewModel.setMessageFeedback(messageId: message.id, feedback: .like) },
                onDislike: { viewModel.setMessageFeedback(messageId: message.id, feedback: .dislike) }
            ),
            isLiveChat: isLiveChat,
            assignedAgent: assignedAgent
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy, state: ChatUiState) {
        guard let lastId = state.isAgentTyping ? "typing-indicator" : listMessages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

private struct FormFieldTarget: Identifiable {
    var messageId: String
    var fieldIndex: Int
    var id: String { "\(messageId)-\(fieldIndex)" }
}
