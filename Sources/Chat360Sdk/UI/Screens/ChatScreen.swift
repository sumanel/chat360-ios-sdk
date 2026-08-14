import SwiftUI

@available(iOS 16.0, *)
public struct ChatScreen: View {
    @ObservedObject private var viewModel: ChatViewModel
    @Environment(\.chat360Colors) private var baseColors
    @Environment(\.chat360Branding) private var baseBranding
    @Environment(\.chat360ThemeController) private var themeController
    @Environment(\.chat360IsDarkTheme) private var isDarkTheme
    @Environment(\.chat360UIConfig) private var sdkConfig
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var voiceRecorder = VoiceRecorderController()
    @StateObject private var voicePreviewPlayback = VoicePlaybackController()
    @StateObject private var speechToText = SpeechToTextController()

    @State private var showEmojiPicker = false
    @State private var showHistorySidebar = false
    @State private var isTrainingMode = false
    @State private var showAttachmentPicker = false
    @State private var showCameraCapture = false
    @FocusState private var isInputFocused: Bool

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    private var effectiveBranding: Chat360Branding {
        var branding = baseBranding
        branding.botTitle = viewModel.uiState.botTitleOverride ?? baseBranding.botTitle
        branding.logo = viewModel.uiState.logoOverride ?? baseBranding.logo
        return branding
    }

    private var features: Chat360FeatureConfig { sdkConfig.features }

    private var pinnedWelcomeMessage: ChatMessage? {
        guard let last = viewModel.uiState.messages.last, !last.fromUser else { return nil }
        if case .welcomeScreen = last.content { return last }
        return nil
    }

    private var listMessages: [ChatMessage] {
        pinnedWelcomeMessage != nil ? Array(viewModel.uiState.messages.dropLast()) : viewModel.uiState.messages
    }

    private func pickAttachment(url: URL) {
        guard let payload = readAttachment(url: url) else { return }
        viewModel.sendFile(bytes: payload.bytes, fileName: payload.fileName, mimeType: payload.mimeType)
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let header = sdkConfig.ui.header {
                    header()
                } else {
                    HeaderBar(
                        connected: viewModel.uiState.isConnected,
                        assignedAgent: viewModel.uiState.assignedAgent,
                        showMenu: features.showMenu && features.showHistorySidebar,
                        showNewChat: features.showNewChat,
                        newChatEnabled: !viewModel.uiState.isAgentTyping,
                        onMenuClick: {
                            sdkConfig.callbacks.onMenuClicked()
                            isInputFocused = false
                            showHistorySidebar = true
                        },
                        onNewChatClick: {
                            sdkConfig.callbacks.onNewChatClicked()
                            viewModel.startNewChat()
                        },
                        shortcuts: viewModel.shortcuts,
                        onShortcutSelected: { targetId, label in viewModel.selectShortcut(targetId: targetId, label: label) },
                        onRefreshClick: { viewModel.refreshConnection() },
                        onCloseClick: { Chat360Bot.shared.closeChatBot() }
                    )
                }

                if viewModel.uiState.isSlowConnection {
                    StatusBanner(text: "Slow connection…", emphasized: false)
                }
                if !viewModel.uiState.isConnected, let error = viewModel.uiState.error {
                    StatusBanner(text: error, emphasized: true)
                }

                if let pinned = pinnedWelcomeMessage {
                    BotMessageItem(message: pinned, viewModel: viewModel, pickAttachment: { showAttachmentPicker = true }, captureFromCamera: { showCameraCapture = true }, isLiveChat: viewModel.uiState.isLiveChat, assignedAgent: viewModel.uiState.assignedAgent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                if viewModel.uiState.messages.isEmpty {
                    WelcomeSplash().frame(maxHeight: .infinity)
                } else if !listMessages.isEmpty || viewModel.uiState.isAgentTyping {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if viewModel.uiState.isLoadingMoreHistory {
                                    HStack {
                                        Spacer()
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: baseColors.accent))
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .id("loading_more_history")
                                    .onAppear { viewModel.loadMoreHistory() }
                                }
                                ForEach(listMessages) { message in
                                    Group {
                                        if message.fromUser {
                                            UserMessageRow(message: message)
                                        } else {
                                            BotMessageItem(message: message, viewModel: viewModel, pickAttachment: { showAttachmentPicker = true }, captureFromCamera: { showCameraCapture = true }, isLiveChat: viewModel.uiState.isLiveChat, assignedAgent: viewModel.uiState.assignedAgent)
                                        }
                                    }
                                    .id(message.id)
                                }
                                if viewModel.uiState.isAgentTyping && features.showTypingIndicator {
                                    TypingIndicatorRow().id("typing_indicator")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: viewModel.uiState.messages.last?.id) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: viewModel.uiState.isAgentTyping) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }

                if viewModel.uiState.isArchived {
                    StatusBanner(text: "This conversation has been archived due to inactivity.", emphasized: false)
                } else if voiceRecorder.isRecording || viewModel.uiState.voiceDraft != nil {
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
                        draftAmplitudes: viewModel.uiState.voiceDraft?.amplitudes ?? [],
                        draftDurationMs: viewModel.uiState.voiceDraft?.durationMs ?? 0,
                        draftUploading: viewModel.uiState.voiceDraft?.uploading ?? false,
                        draftUploadProgress: viewModel.uiState.voiceDraft?.uploadProgress ?? 0,
                        draftError: viewModel.uiState.voiceDraft?.error,
                        playbackController: voicePreviewPlayback,
                        draftLocalFilePath: viewModel.uiState.voiceDraft?.filePath,
                        onSendDraft: { viewModel.sendVoiceDraft() },
                        onCancelDraft: {
                            voicePreviewPlayback.pause()
                            viewModel.cancelVoiceDraft()
                        }
                    )
                } else if speechToText.isListening {
                    SpeechToTextBar(isListening: true, error: speechToText.error, onStop: { speechToText.stop() })
                } else {
                    if showEmojiPicker {
                        EmojiPickerPanel(onEmojiSelected: { emoji in viewModel.onInputChange(viewModel.uiState.inputText + emoji) })
                    }
                    if let footer = sdkConfig.ui.footer {
                        footer()
                    } else {
                        ChatInputBar(
                            value: Binding(get: { viewModel.uiState.inputText }, set: { viewModel.onInputChange($0) }),
                            isFocused: $isInputFocused,
                            onSend: {
                                viewModel.sendMessage()
                                isInputFocused = false
                            },
                            onAttachmentClick: { showAttachmentPicker = true },
                            onMicClick: { voiceRecorder.requestStart() },
                            showDictationIcon: features.showSpeechToText && speechToText.isSupported(),
                            onDictateClick: { speechToText.requestStart() },
                            onEmojiClick: { showEmojiPicker.toggle() },
                            showAttachment: features.showAttachment,
                            showEmoji: features.showEmoji,
                            showVoiceInput: features.showVoiceInput,
                            showSend: features.showSend,
                            sendEnabled: !viewModel.uiState.isAgentTyping,
                            enabled: viewModel.uiState.isConnected
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(baseColors.background)

            if showHistorySidebar && features.showHistorySidebar {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ChatDrawer(
                            onDismiss: { showHistorySidebar = false },
                            onNewChat: {
                                viewModel.startNewChat()
                                showHistorySidebar = false
                            },
                            isTrainingMode: isTrainingMode,
                            onAssistantModeChanged: { isTrainingMode = $0 },
                            isDarkTheme: isDarkTheme ?? false,
                            onThemeChanged: { themeController?.selectDarkTheme($0) },
                            showAssistantMode: features.showAssistantMode,
                            showAppearanceSwitcher: features.showAppearanceSwitcher && sdkConfig.theme.allowThemeSwitch,
                            conversations: viewModel.conversations,
                            activeConversationId: viewModel.uiState.activeConversationId,
                            onConversationSelected: {
                                viewModel.openConversation($0)
                                showHistorySidebar = false
                            },
                            onConversationRenamed: { id, title in viewModel.renameConversation(conversationId: id, title: title) },
                            onConversationDeleted: { viewModel.deleteConversation($0) },
                            languages: viewModel.languages,
                            onLanguageSelected: { key in
                                viewModel.switchLanguage(targetId: key)
                                showHistorySidebar = false
                            }
                        )
                        .frame(width: min(320, geo.size.width * 0.84))
                        Spacer(minLength: 0)
                    }
                }
                .background(Color.black.opacity(0.55))
                .onTapGesture { showHistorySidebar = false }
                .transition(.move(edge: .leading))
                .animation(.easeOut(duration: 0.22), value: showHistorySidebar)
            }

            if viewModel.uiState.showFeedbackPrompt, let feedbackConfig = viewModel.uiState.feedbackConfig {
                Color.black.opacity(0.4).ignoresSafeArea()
                FeedbackFormDialog(
                    feedbackConfig: feedbackConfig,
                    onSubmit: { rating, text in viewModel.submitFeedback(rating: rating, feedbackText: text) },
                    onDismiss: { viewModel.dismissFeedbackPrompt() }
                )
            }
        }
        .onDisappear {
            viewModel.onCleared()
        }
        .onChange(of: speechToText.transcript) { transcript in
            if speechToText.isListening { viewModel.onInputChange(transcript) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { viewModel.onAppForegrounded() }
        }
        .onChange(of: viewModel.uiState.pendingUrlToOpen) { url in
            guard let url, let resolved = URL(string: url) else { return }
            openURL(resolved)
            viewModel.clearPendingUrl()
        }
        .fileImporter(isPresented: $showAttachmentPicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            guard let url = try? result.get().first else { return }
            pickAttachment(url: url)
        }
        .sheet(isPresented: $showCameraCapture) {
            CameraCaptureView { data in
                viewModel.sendFile(bytes: data, fileName: "chat360_camera_\(Int64(Date().timeIntervalSince1970 * 1000)).jpg", mimeType: "image/jpeg")
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if viewModel.uiState.isAgentTyping {
                proxy.scrollTo("typing_indicator", anchor: .bottom)
            } else if let lastId = listMessages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct BotMessageItem: View {
    let message: ChatMessage
    let viewModel: ChatViewModel
    let pickAttachment: () -> Void
    let captureFromCamera: () -> Void
    let isLiveChat: Bool
    let assignedAgent: AssignedAgent?

    var body: some View {
        var actions = BotContentActions()
        actions.onQuickReply = { option in viewModel.selectQuickReply(messageId: message.id, option: option) }
        actions.onAttachmentClick = pickAttachment
        actions.onCameraClick = captureFromCamera
        actions.onRatingSelected = { value in viewModel.selectRating(messageId: message.id, value: value) }
        actions.onFormFieldChange = { index, value in viewModel.updateFormField(messageId: message.id, fieldIndex: index, value: value) }
        actions.onMediaFieldPicked = { index, bytes, fileName, mimeType in viewModel.uploadFormField(messageId: message.id, bytes: bytes, fieldIndex: index, fileName: fileName, mimeType: mimeType) }
        actions.onFormSubmit = { viewModel.submitForm(messageId: message.id) }
        actions.onPromptValueChange = { primary, secondary in viewModel.updatePromptValue(messageId: message.id, primary: primary, secondary: secondary) }
        actions.onEmailSubmit = { viewModel.submitEmail(messageId: message.id) }
        actions.onPhoneSubmit = { viewModel.submitPhone(messageId: message.id) }
        actions.onAutoSuggestionSelected = { index, text in viewModel.selectAutoSuggestion(messageId: message.id, index: index, text: text) }
        actions.onDateSelected = { date in viewModel.selectDate(messageId: message.id, formattedDate: date) }
        actions.onTimeSubmit = { time in viewModel.submitTime(messageId: message.id, formattedTime: time) }
        actions.onCheckboxToggle = { index in viewModel.toggleCheckbox(messageId: message.id, index: index) }
        actions.onCheckboxSubmit = { viewModel.submitCheckboxes(messageId: message.id) }
        actions.onImageButtonClick = { card, button in
            var submitType = "BUTTON"
            if case .imageButtons(let content) = message.content { submitType = content.submitType }
            viewModel.selectImageButton(messageId: message.id, card: card, button: button, submitType: submitType)
        }
        actions.onTextCarouselTap = { text, index, targetId in viewModel.selectTextCarouselReply(messageId: message.id, text: text, clickedIndex: index, targetId: targetId) }
        actions.onWelcomeCardSelected = { card, index in viewModel.selectWelcomeCard(messageId: message.id, card: card, index: index) }
        actions.onIframeAdvance = { targetId in viewModel.advanceFromIframe(targetId: targetId) }
        actions.onRegenerateClicked = { viewModel.regenerateMessage(messageId: message.id) }

        return BotMessageRow(message: message, actions: actions, isLiveChat: isLiveChat, assignedAgent: assignedAgent)
    }
}
