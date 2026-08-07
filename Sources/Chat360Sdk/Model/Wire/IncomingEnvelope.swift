import Foundation

/// Loose decode target for any server -> client socket frame. Fields are the ones actually read
/// by the dispatch chain below (close/ack/echo/typing/bot) - everything else is discarded rather
/// than guessed at.
public struct RawSocketEnvelope: Codable, Equatable {
    public var user: String? = nil
    public var type: String? = nil
    public var data: JSONValue? = nil
    public var message: JSONValue? = nil
    public var chat_msg_id: String? = nil
    public var status: String? = nil
    public var targetId: String? = nil
    public var error: String? = nil
    // chatgpt_message streaming fields live at this level, sibling to `type`/`user`, not nested
    // inside `data`.
    public var stream_id: String? = nil
    public var end_stream: Bool? = nil
    /// The live-chat "end" signal - a boolean flag on any incoming frame.
    public var update_status: Bool? = nil
    /// Sibling to `type`/`data` on a `chat_inactivity_message` frame.
    public var auto_archival: Bool? = nil

    public init(
        user: String? = nil,
        type: String? = nil,
        data: JSONValue? = nil,
        message: JSONValue? = nil,
        chat_msg_id: String? = nil,
        status: String? = nil,
        targetId: String? = nil,
        error: String? = nil,
        stream_id: String? = nil,
        end_stream: Bool? = nil,
        update_status: Bool? = nil,
        auto_archival: Bool? = nil
    ) {
        self.user = user
        self.type = type
        self.data = data
        self.message = message
        self.chat_msg_id = chat_msg_id
        self.status = status
        self.targetId = targetId
        self.error = error
        self.stream_id = stream_id
        self.end_stream = end_stream
        self.update_status = update_status
        self.auto_archival = auto_archival
    }
}

/// Typed result of dispatching a `RawSocketEnvelope` through the dispatch chain.
public enum IncomingSocketEvent: Equatable {
    case pong
    case closeConnection(suppressReconnect: Bool)
    case ack(chatMsgId: String?)
    /// `text` is the user's own message text, present so history/cache replay can reconstruct the
    /// user's side of the conversation - a live echo already rendered optimistically at send time,
    /// so callers should only render this when replaying (from cache or a REST history fetch).
    case echoedUserMessage(chatMsgId: String?, text: String?)
    case typingStatus(isTyping: Bool)
    case botMessage(BotNode)
    /// A `highlight` frame's `assigned_user` - takes precedence over any other msgType the same frame might carry.
    case agentAssigned(AssignedAgent)
    /// `update_status` - ends the live-chat segment.
    case liveChatEnded
    /// A `chat_inactivity_message` frame - `message` only set for its `type:'message'` sub-case;
    /// `autoArchive` mirrors `auto_archival` (session is being closed for inactivity).
    case inactivityNotice(message: String?, autoArchive: Bool)
    case unhandled(RawSocketEnvelope)
}

/// Mirrors the server's handler chain order exactly - order matters, since e.g. a
/// close_connection or ack frame must never fall through and get misread as bot content:
/// close_connection -> ack -> echoed end_user -> typing_status -> update_status -> highlight
/// (assigned_user, which takes precedence over any other msgType the same frame carries) ->
/// bot/agent content.
public extension RawSocketEnvelope {
    func toIncomingEvent() -> IncomingSocketEvent {
        if type == "pong" { return .pong }

        if type == "close_connection" {
            let messageText = message?.contentOrNull ?? ""
            let suppress = error == "CONNECTION_CLOSE" || messageText.lowercased().contains("other window or tab")
            return .closeConnection(suppressReconnect: suppress)
        }

        if type == "ack" && status == "sent" {
            return .ack(chatMsgId: chat_msg_id)
        }

        if user == "end_user" {
            return .echoedUserMessage(chatMsgId: chat_msg_id, text: message?.contentOrNull)
        }

        if type == "typing_status" {
            return .typingStatus(isTyping: status == "typing")
        }

        if update_status == true {
            return .liveChatEnded
        }

        if type == "chat_inactivity_message" {
            let isMessage = data?["type"]?.contentOrNull == "message"
            let text = isMessage ? data?["message"]?.contentOrNull : nil
            return .inactivityNotice(message: text, autoArchive: auto_archival == true)
        }

        // No widget renders `validation_error` specially - the frame's own top-level `message` is
        // displayed as a plain bot bubble, same as any other text-only node.
        if type == "validation_error" {
            let text = message?.contentOrNull.flatMap { $0.isEmpty ? nil : $0 }
            return .botMessage(BotNode(
                nodeId: nil,
                nodeType: "validation_error",
                targetId: targetId,
                variable: nil,
                text: text,
                content: text != nil ? .plainText : .unsupported(nodeType: "validation_error")
            ))
        }

        if let assignedUserObj = data?["assigned_user"], !assignedUserObj.isEmptyObject, assignedUserObj.objectValue != nil {
            return .agentAssigned(assignedUserObj.toAssignedAgent())
        }

        if (user == "bot" || user == "admin" || user == "operator"), let data {
            let node = data.toBotNode(fallbackTargetId: targetId)
            var authored = node
            if user != "bot" { authored.author = .agent }
            // msgType = data.nodeType || type || 'message': data.nodeType wins when present, so
            // only treat this as a streaming chunk when the node has no nodeType of its own.
            // chatgpt_message streaming is bot-origin only, so this never applies to admin/operator.
            if user == "bot" && (authored.nodeType?.isEmpty ?? true) && type == "chatgpt_message" {
                authored.streamId = stream_id
                authored.streamEnded = end_stream ?? true
            }
            return .botMessage(authored)
        }

        // A chatgpt_message chunk with no nested `data` at all still carries its text via the
        // envelope's own top-level `message` field.
        if user == "bot" && type == "chatgpt_message" {
            // Text stays as raw (unrendered) HTML here - a chunk boundary can land inside a tag,
            // so a tag split across two chunks never forms a complete "<...>" in either one on its
            // own. The view model concatenates every chunk before RichTextParser ever sees the
            // string, so a split tag is always whole again by the time it's parsed.
            let chunkText = message?.contentOrNull.map { $0.normalizedNewlines() }.flatMap { $0.isEmpty ? nil : $0 }
            return .botMessage(BotNode(
                nodeId: nil,
                nodeType: "chatgpt_message",
                targetId: targetId,
                variable: nil,
                text: chunkText,
                content: chunkText != nil ? .plainText : .unsupported(nodeType: "chatgpt_message"),
                streamId: stream_id,
                streamEnded: end_stream ?? true
            ))
        }

        return .unhandled(self)
    }
}

/// Ports the highlight-message extraction: `assigned_user -> {avatar, user_designation, operator_name}`.
private extension JSONValue {
    func toAssignedAgent() -> AssignedAgent {
        AssignedAgent(
            name: string("operator_name").flatMap { $0.isEmpty ? nil : $0 },
            designation: string("user_designation").flatMap { $0.isEmpty ? nil : $0 },
            avatarUrl: string("avatar").flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

extension JSONValue {
    func toBotNode(fallbackTargetId: String? = nil) -> BotNode {
        let nodeType = string("nodeType")
        let nodeTargetId = string("targetId") ?? fallbackTargetId
        let variables = variablesMap()

        // Buttons whose text is an @variable reference are kept only when every referenced
        // variable has a non-blank value - an LLM/webhook node's placeholder buttons stay hidden
        // until the populated frame arrives.
        let options: [BotContent.MultiChoice.Option] = (self["buttons"]?.arrayValue ?? []).enumerated().compactMap { index, element in
            guard let rawText = element.string("text") else { return nil }
            guard isTextPopulated(rawText, variables) else { return nil }
            return BotContent.MultiChoice.Option(
                index: index,
                text: resolveVariables(rawText, variables).strippingHtml(),
                targetId: element.string("targetId")
            )
        }

        let rawText = botDisplayText()
        // LINK bifurcates: with no separate question text, the URL itself becomes the message (a
        // plain linkified bubble); only when question text already exists does the URL become its
        // own separate clickable card alongside it.
        let linkUrl: String? = nodeType == "LINK" ? string("urlMessage").map { resolveVariables($0, variables) } : nil
        let text: String? = {
            let base = (nodeType == "LINK" && (rawText?.isEmpty ?? true)) ? linkUrl : rawText
            guard let base else { return nil }
            let resolved = resolveVariables(base, variables).normalizedNewlines()
            return resolved.isEmpty ? nil : resolved
        }()

        // YES_NO reuses MULTI_CHOICE's own extractor/renderer exactly - same shape, same payload.
        let content: BotContent
        if (nodeType == "MULTI_CHOICE" || nodeType == "YES_NO") && !options.isEmpty {
            content = .multiChoice(.init(variant: string("choiceType"), options: options))
        } else {
            content = dispatchRemainingContent(nodeType: nodeType, nodeTargetId: nodeTargetId, text: text, rawText: rawText, linkUrl: linkUrl, variables: variables)
        }

        return BotNode(
            nodeId: string("id"),
            nodeType: nodeType,
            targetId: nodeTargetId,
            variable: string("variable").flatMap { $0.isEmpty ? nil : $0 },
            text: text,
            content: content,
            endUrlMessage: nodeType == "END" ? string("urlMessage").flatMap { $0.isEmpty ? nil : $0 } : nil,
            endSessionRequested: nodeType == "END" && boolean("end_session")
        )
    }

    private func dispatchRemainingContent(nodeType: String?, nodeTargetId: String?, text: String?, rawText: String?, linkUrl: String?, variables: [String: String]) -> BotContent {
        switch nodeType {
        case "MEDIA":
            return mediaContent(variables) ?? .unsupported(nodeType: nodeType)
        case "CAROUSEL":
            return carouselContent(variables) ?? .unsupported(nodeType: nodeType)
        case "FILE_UPLOAD":
            return fileUploadContent(variables)
        case "DOWNLOAD_MEDIA":
            return downloadMediaContent(variables) ?? .unsupported(nodeType: nodeType)
        case "RATING":
            return ratingContent()
        case "FORM":
            return formContent(variables) ?? .unsupported(nodeType: nodeType)
        case "WINDOW_EVENT":
            return windowEventContent(variables)
        case "EMAIL":
            return .emailPrompt
        case "PHONE":
            return phoneContent()
        // CUSTOMINPUT is two behaviors sharing one nodeType: an explicit AUTOSUGGESTION picker, or
        // (far more commonly) a plain free-text prompt - which the always-visible input bar
        // already answers via the generic PlainText fallback below.
        case "CUSTOMINPUT":
            return autoSuggestionContent(variables).map { BotContent.autoSuggestion($0) } ?? (text != nil ? .plainText : .unsupported(nodeType: nodeType))
        case "DATE":
            return .datePrompt(.init(rules: standaloneDateRules()))
        case "TIME":
            return timeContent()
        case "MULTIPLE_CHECK_BOX":
            return multiOptionContent(variables) ?? .unsupported(nodeType: nodeType)
        case "IMAGE_BUTTON":
            return imageButtonContent(variables) ?? .unsupported(nodeType: nodeType)
        case "TEXT_CAROUSEL":
            return textCarouselContent(variables) ?? .unsupported(nodeType: nodeType)
        case "LINK":
            return (!(rawText?.isEmpty ?? true) && linkUrl != nil) ? .linkCard(.init(url: linkUrl!)) : .plainText
        case "AGENT_TRANSFER", "TEAM_TRANSFER":
            return .agentTransferNotice
        // chat_feedback_data forces msgType FEEDBACK for the post-chat "rate this conversation"
        // prompt - distinct trigger from an in-flow RATING node, but the same UI/send path.
        case "FEEDBACK":
            return ratingContent()
        case "WELCOME_SCREEN":
            return welcomeScreenContent(variables) ?? .unsupported(nodeType: nodeType)
        case "IFRAME":
            return iframeContent(nodeTargetId: nodeTargetId) ?? .unsupported(nodeType: nodeType)
        default:
            return text != nil ? .plainText : .unsupported(nodeType: nodeType)
        }
    }

    private func variablesMap() -> [String: String] {
        guard let dict = self["variables"]?.objectValue else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict where !key.isEmpty && key != "@" {
            result[key] = value.contentOrNull ?? ""
        }
        return result
    }

    /// Ports `_parseMedia()`: a single media item, media_url + optional title/download flag.
    private func mediaContent(_ variables: [String: String]) -> BotContent? {
        guard let rawUrl = string("media_url") else { return nil }
        let url = resolveVariables(rawUrl, variables)
        let title = string("media_title").map { resolveVariables($0, variables) }
        let dynamicButtons = dynamicButtonsList(key: "dynamic_buttons", variables: variables)
        return .media(.init(
            url: url,
            kind: mediaKind(of: url),
            title: title,
            downloadDisabled: boolean("disable_download"),
            dynamicButtons: dynamicButtons
        ))
    }

    /// Ports `_extractCarouselData()`: parallel arrays (carousel_url/links/captions/headings) -> cards.
    private func carouselContent(_ variables: [String: String]) -> BotContent? {
        guard let urlEntries = self["carousel_url"]?.arrayValue else { return nil }
        let links = self["link_carousel"]?.arrayValue?.stringsOrNull()
        let captions = self["caption_carousel"]?.arrayValue?.stringsOrNull()
        let headings = self["heading_carousel"]?.arrayValue?.stringsOrNull()

        let cards: [BotContent.Carousel.Card] = urlEntries.enumerated().compactMap { index, entry in
            guard let rawUrl = entry.arrayValue?.first?.contentOrNull else { return nil }
            return BotContent.Carousel.Card(
                imageUrl: resolveVariables(rawUrl, variables),
                heading: headings?.at(index).map { resolveVariables($0, variables).strippingHtml() },
                caption: captions?.at(index).map { resolveVariables($0, variables).strippingHtml() },
                link: links?.at(index).map { resolveVariables($0, variables) }.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        return cards.isEmpty ? nil : .carousel(.init(cards: cards))
    }

    /// Ports `_parseFileUpload()`: which extensions the node accepts, keyed off its fileType toggles.
    private func fileUploadContent(_ variables: [String: String]) -> BotContent {
        let extensionsByKey: [String: [String]] = [
            "image": ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "jfif"],
            "video": ["mp4", "webm", "mov", "ogv", "avi", "hevc", "m4v"],
            "document": ["pdf", "doc", "docx", "odt", "txt", "xlsx", "csv", "zip"],
            "audio": ["mp3", "wav", "ogg", "ogx"],
            "pdf": ["pdf"],
        ]
        let toggles = self["fileType"]?.arrayValue ?? []
        var extensions: [String] = []
        for entry in toggles {
            let enabled = entry.boolean("value")
            guard enabled, let key = entry.string("key")?.lowercased() else { continue }
            extensions.append(contentsOf: extensionsByKey[key] ?? [])
        }
        var seen = Set<String>()
        extensions = extensions.filter { seen.insert($0).inserted }
        // No type toggles enabled at all -> default to accepting everything.
        let allowed = extensions.isEmpty ? Array(Set(extensionsByKey.values.flatMap { $0 })) : extensions
        let prompt = string("questionText").map { resolveVariables($0, variables).strippingHtml() }
        return .fileUploadPrompt(.init(promptText: prompt, allowedExtensions: allowed, allowCamera: boolean("enableCameraInput")))
    }

    /// Ports `_extractFileName()`: a downloadable link, named either explicitly or from the URL.
    private func downloadMediaContent(_ variables: [String: String]) -> BotContent? {
        guard let rawUrl = string("media_url") else { return nil }
        let url = resolveVariables(rawUrl, variables)
        let derived = url.split(separator: "/").last.map(String.init)?.split(separator: "?").first.map(String.init)
        let name = string("mediaName") ?? (derived?.isEmpty == false ? derived! : "download")
        return .downloadMedia(.init(fileUrl: url, fileName: name))
    }

    /// Ports `_extractRatingData()`: star_custom -> star (scale = rating_max, default 5), else emoji (fixed scale of 5).
    private func ratingContent() -> BotContent {
        let style = string("rating_type") == "star_custom" ? "star" : "emoji"
        let scale = style == "star" ? (string("rating_max").flatMap { Int($0) } ?? 5) : 5
        return .rating(.init(style: style, scale: scale))
    }

    /// Ports `_extractFormData()`: one Field per `elements[]` entry.
    private func formContent(_ variables: [String: String]) -> BotContent? {
        guard let elements = self["elements"]?.arrayValue else { return nil }
        let fields: [BotContent.Form.Field] = elements.enumerated().compactMap { index, element in
            guard element.objectValue != nil else { return nil }
            let fieldType: BotContent.Form.FieldType
            switch element.string("type")?.uppercased() {
            case "TEXT": fieldType = .text
            case "NUMBER": fieldType = .number
            case "EMAIL": fieldType = .email
            case "PHONE": fieldType = .phone
            case "SELECT": fieldType = .select
            case "DATE": fieldType = .date
            case "MEDIA": fieldType = .media
            default: fieldType = .other
            }
            let options = (element["options"]?.arrayValue?.stringsOrNull() ?? [])
                .compactMap { $0 }
                .map { resolveVariables($0, variables) }
            let validation = element.fieldValidation(dateFormat: element.string("dateFormat"))
            let label = element.string("label").map { resolveVariables($0, variables).strippingHtml() }.flatMap { $0.isEmpty ? nil : $0 }
            return BotContent.Form.Field(
                index: index,
                type: fieldType,
                label: label,
                placeholder: element.string("placeholder").map { resolveVariables($0, variables) },
                // The parser separately reads a flat isRequired for its "is this form skippable"
                // check - honor either spelling so a backend using only the flat form still
                // enforces required-ness.
                isRequired: validation?.isRequired == true || element.boolean("isRequired"),
                options: options,
                variable: element.string("variable").flatMap { $0.isEmpty ? nil : $0 },
                validation: validation
            )
        }
        if fields.isEmpty { return nil }
        let submitText = string("submitButtonText").map { resolveVariables($0, variables) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Submit"
        return .form(.init(fields: fields, submitButtonText: submitText))
    }

    /// Ports the widget's per-element `validation` object.
    private func fieldValidation(dateFormat: String?) -> BotContent.Form.FieldValidation? {
        guard let v = self["validation"], v.objectValue != nil else { return nil }
        let dateRules: DateRules?
        if v.containsAnyDateKey() {
            dateRules = DateRules(
                isScheduledDate: v.boolean("isScheduledDate"),
                disabledDays: v["disabledDays"]?.arrayValue?.map { $0.boolOrNull == true },
                disabledDates: v["disableDates"]?.arrayValue?.stringsOrNull().compactMap { $0 },
                // FORM's own field names for these two flags (isFutureDisabled/isPrevDisabled)
                // differ from the standalone DATE node's (isFutureDate/isPrevDate) - ported as-is.
                disableFuture: v.boolean("isFutureDisabled"),
                disablePrevious: v.boolean("isPrevDisabled"),
                dateFormat: dateFormat.flatMap { $0.isEmpty ? nil : $0 } ?? "DD MMM YYYY"
            )
        } else {
            dateRules = nil
        }
        return BotContent.Form.FieldValidation(
            isRequired: v.boolean("isRequired"),
            errorMessage: v.string("errorMessage").flatMap { $0.isEmpty ? nil : $0 },
            userInputType: v.string("userInputType"),
            maxCharacters: v.int("maxCharacters"),
            minCharacters: v.int("minCharacters"),
            email: v.boolean("email"),
            maxCount: v.double("maxCount"),
            minCount: v.double("minCount"),
            phone: v.boolean("phone"),
            allowInternationalNumber: v.boolean("allowInternationalNumber"),
            numberFormat: v.string("numberFormat"),
            dateRules: dateRules
        )
    }

    private func containsAnyDateKey() -> Bool {
        containsKey("isScheduledDate") || containsKey("disableDates") || containsKey("isFutureDisabled") || containsKey("isPrevDisabled")
    }

    /// Ports `_extractDateData()`'s core rules for a standalone DATE node.
    private func standaloneDateRules() -> DateRules {
        DateRules(
            isScheduledDate: boolean("isScheduledDate"),
            disabledDays: self["disabledDays"]?.arrayValue?.map { $0.boolOrNull == true },
            disabledDates: self["disabledDates"]?.arrayValue?.stringsOrNull().compactMap { $0 },
            disableFuture: boolean("isFutureDate"),
            disableCurrent: boolean("isCurrentDate"),
            disablePrevious: boolean("isPrevDate"),
            manageWithVariable: boolean("manageWithVariable"),
            variableMode: string("variableMode"),
            variableDates: string("datesVariable")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            dateFormat: string("dateFormat").flatMap { $0.isEmpty ? nil : $0 } ?? "DD MMM YYYY"
        )
    }

    /// Ports `_extractTimeData()`: disabledSlots is "hh:mm-hh:mm" range strings, expanded to hour->minutes.
    private func timeContent() -> BotContent {
        let slots = self["disabledSlots"]?.arrayValue?.stringsOrNull().compactMap { $0 } ?? []
        var disabled: [Int: [Int]] = [:]
        for range in slots {
            let parts = range.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let startParts = parts[0].split(separator: ":").compactMap { Int($0) }
            let endParts = parts[1].split(separator: ":").compactMap { Int($0) }
            guard startParts.count == 2, endParts.count == 2 else { continue }
            var hour = startParts[0]
            var minute = startParts[1]
            let endHour = endParts[0]
            let endMinute = endParts[1]
            while hour < endHour || (hour == endHour && minute <= endMinute) {
                disabled[hour, default: []].append(minute)
                minute += 1
                if minute > 59 {
                    minute = 0
                    hour += 1
                }
            }
        }
        return .timePrompt(.init(disabledSlots: disabled, disablePrevious: boolean("disablePrev")))
    }

    /// Ports `_extractWindowEventData()`: should_send_data defaults true, send_data values go
    /// through the same @variable substitution as everything else.
    private func windowEventContent(_ variables: [String: String]) -> BotContent {
        let shouldSend = self["should_send_data"]?.boolOrNull ?? true
        let shouldReceive = self["should_receive_data"]?.boolOrNull ?? false
        var sendData: [String: String] = [:]
        if let dict = self["send_data"]?.objectValue {
            for (key, value) in dict {
                guard let raw = value.contentOrNull else { continue }
                sendData[key] = resolveVariables(raw, variables)
            }
        }
        return .windowEvent(.init(shouldSend: shouldSend, sendData: sendData, shouldReceive: shouldReceive))
    }

    /// Ports `_extractPhoneData()`: international mode is the only variant with a dedicated widget/validation.
    private func phoneContent() -> BotContent {
        .phonePrompt(.init(
            allowInternational: boolean("allowInternationalNumber"),
            splitVariable: boolean("split_variable"),
            countryCodeVar: string("country_code_var").flatMap { $0.isEmpty ? nil : $0 }
        ))
    }

    /// Ports `_extractMultiOptionData()`: choices is a plain string array, filtered like MULTI_CHOICE's buttons.
    private func multiOptionContent(_ variables: [String: String]) -> BotContent? {
        guard let choices = self["choices"]?.arrayValue else { return nil }
        let options: [BotContent.MultiOption.Option] = choices.enumerated().compactMap { index, element in
            guard let rawText = element.contentOrNull else { return nil }
            guard isTextPopulated(rawText, variables) else { return nil }
            return BotContent.MultiOption.Option(index: index, text: resolveVariables(rawText, variables).strippingHtml())
        }
        if options.isEmpty { return nil }
        let description = (string("description") ?? string("questionText"))
            .map { resolveVariables($0, variables).strippingHtml() }
            .flatMap { $0.isEmpty ? nil : $0 }
        return .multiOption(.init(description: description, options: options))
    }

    private struct RawImageButton {
        var text: String
        var type: String
        var value: String?
        var url: String?
    }

    /// Ports `_extractImageButtonData()`: per-slide buttons come from `img_buttons` (falling back
    /// to the legacy `link_carousel_text`, one reply button per slide); each button's targetId is
    /// resolved from the flat `buttons` array by cumulative position across all slides.
    private func imageButtonContent(_ variables: [String: String]) -> BotContent? {
        guard let urlEntries = self["carousel_url"]?.arrayValue else { return nil }
        let descriptions = self["link_carousel"]?.arrayValue?.stringsOrNull()
        let flatButtons = self["buttons"]?.arrayValue?.filter { $0.objectValue != nil } ?? []

        var perSlideButtons: [[RawImageButton]] = []
        if let imgButtons = self["img_buttons"]?.arrayValue {
            perSlideButtons = imgButtons.map { slide in
                (slide.arrayValue ?? []).compactMap { entry -> RawImageButton? in
                    guard entry.objectValue != nil else { return nil }
                    return RawImageButton(
                        text: entry.string("text") ?? "",
                        type: entry.string("type") ?? "reply",
                        value: entry.string("value"),
                        url: entry.string("url")
                    )
                }
            }
        } else if let legacy = self["link_carousel_text"]?.arrayValue {
            perSlideButtons = legacy.map { entry in
                if let text = entry.contentOrNull {
                    return [RawImageButton(text: text, type: "reply", value: nil, url: nil)]
                }
                return []
            }
        }

        var flatIndex = 0
        let cards: [BotContent.ImageButtons.Card] = urlEntries.enumerated().compactMap { index, entry in
            guard let rawUrl = entry.arrayValue?.first?.contentOrNull else { return nil }
            let raws = index < perSlideButtons.count ? perSlideButtons[index] : []
            let buttons: [BotContent.ImageButtons.Button] = raws.map { raw in
                let targetId = flatIndex < flatButtons.count ? flatButtons[flatIndex].string("targetId") : nil
                flatIndex += 1
                return BotContent.ImageButtons.Button(
                    text: resolveVariables(raw.text, variables),
                    type: raw.type,
                    value: resolveVariables(raw.value ?? raw.text, variables),
                    url: raw.url.map { resolveVariables($0, variables) },
                    targetId: targetId
                )
            }
            return BotContent.ImageButtons.Card(
                imageUrl: resolveVariables(rawUrl, variables),
                description: descriptions?.at(index).map { resolveVariables($0, variables).strippingHtml() },
                buttons: buttons
            )
        }
        if cards.isEmpty { return nil }
        return .imageButtons(.init(cards: cards, submitType: string("submit_type") ?? "BUTTON"))
    }

    private func dynamicButtonsList(key: String, variables: [String: String]) -> [BotContent.TextCarousel.DynamicButton] {
        (self[key]?.arrayValue ?? []).compactMap { entry in
            guard entry.objectValue != nil else { return nil }
            return BotContent.TextCarousel.DynamicButton(
                title: entry.string("title").map { resolveVariables($0, variables) } ?? "",
                targetId: entry.string("targetId").flatMap { $0.isEmpty ? nil : $0 },
                componentUuid: entry.string("componentUuid").flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    /// Ports `_extractTextCarouselData()`: both `type1`/`type2` wire generations map onto one card shape.
    private func textCarouselContent(_ variables: [String: String]) -> BotContent? {
        guard let rawCards = self["text_cards"]?.arrayValue else { return nil }
        let isType2 = string("text_carousel_type") == "type2"
        let cards: [BotContent.TextCarousel.Card] = rawCards.compactMap { entry in
            guard entry.objectValue != nil else { return nil }
            let content = entry.string("content").map { resolveVariables($0, variables).strippingHtml() }
            if !isType2 && (content?.isEmpty ?? true) { return nil }
            let ctaButtons: [BotContent.TextCarousel.CtaButton] = (entry["ctaButtons"]?.arrayValue ?? []).compactMap { btn in
                guard btn.objectValue != nil else { return nil }
                return BotContent.TextCarousel.CtaButton(
                    name: btn.string("name").map { resolveVariables($0, variables) } ?? "",
                    type: btn.string("type") == "component_uuid" ? "component_uuid" : "link",
                    link: btn.string("link") ?? ""
                )
            }
            let buttons: [BotContent.TextCarousel.CardButton] = (entry["buttons"]?.arrayValue ?? []).compactMap { btn in
                guard btn.objectValue != nil else { return nil }
                return BotContent.TextCarousel.CardButton(
                    label: btn.string("label").map { resolveVariables($0, variables) } ?? "",
                    link: btn.string("link")
                )
            }
            return BotContent.TextCarousel.Card(
                name: entry.string("name").flatMap { $0.isEmpty ? nil : $0 },
                content: content,
                bgColor: entry.string("bgColor"),
                bgImage: entry.string("bgImage").flatMap { $0.isEmpty ? nil : $0 },
                footerText: entry.string("footerText").map { resolveVariables($0, variables) },
                iconText: entry.string("iconText").map { resolveVariables($0, variables) },
                iconUrl: entry.string("iconUrl").flatMap { $0.isEmpty ? nil : $0 },
                redirectType: entry.string("redirectType").flatMap { $0.isEmpty ? nil : $0 },
                redirectLink: entry.string("redirectLink").flatMap { $0.isEmpty ? nil : $0 },
                ctaButtons: ctaButtons,
                buttons: buttons
            )
        }
        if cards.isEmpty { return nil }
        let dynamicButtons = dynamicButtonsList(key: "dynamic_buttons", variables: variables)
        return .textCarousel(.init(cards: cards, dynamicButtons: dynamicButtons))
    }

    /// Ports `_extractIFrameData()`: plain embedded WebView, no postMessage bridge beyond `moveForEvent`.
    private func iframeContent(nodeTargetId: String?) -> BotContent? {
        guard let src = string("src"), !src.isEmpty else { return nil }
        return .iframeContent(.init(
            url: src,
            heightDp: int("height"),
            moveForEvent: string("moveForEvent").flatMap { $0.isEmpty ? nil : $0 },
            targetId: nodeTargetId
        ))
    }

    /// Ports `_extractWelcomeScreenData()`.
    private func welcomeScreenContent(_ variables: [String: String]) -> BotContent? {
        let cards: [BotContent.WelcomeScreen.Card] = (self["text_cards"]?.arrayValue ?? []).compactMap { entry in
            guard entry.objectValue != nil else { return nil }
            return BotContent.WelcomeScreen.Card(
                name: entry.string("name").map { resolveVariables($0, variables) },
                title: entry.string("title").map { resolveVariables($0, variables) },
                bgColor: entry.string("bgColor"),
                bgImageUrl: entry.string("bgImageUrl").flatMap { $0.isEmpty ? nil : $0 },
                ctaEnabled: entry.boolean("ctaEnabled"),
                ctaType: entry.string("ctaType") ?? "external_link",
                ctaLink: entry.string("ctaLink").flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        let title = string("title").map { resolveVariables($0, variables) }
        let description = string("description").map { resolveVariables($0, variables) }
        if cards.isEmpty && (title?.isEmpty ?? true) && (description?.isEmpty ?? true) { return nil }
        return .welcomeScreen(.init(
            iconUrl: string("mainIconUrl").flatMap { $0.isEmpty ? nil : $0 },
            title: title,
            description: description,
            cards: cards
        ))
    }

    /// Ports the AUTOSUGGESTION sub-case of CUSTOMINPUT: options are a "{&}"-delimited string.
    private func autoSuggestionContent(_ variables: [String: String]) -> BotContent.AutoSuggestion? {
        guard self["dataType"]?.string("type") == "AUTOSUGGESTION" else { return nil }
        guard let raw = string("autoSuggestionOptions") else { return nil }
        let choices = raw.components(separatedBy: "{&}")
            .map { resolveVariables($0, variables).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if choices.isEmpty { return nil }
        let description = string("autoSuggestionDescription").map { resolveVariables($0, variables).strippingHtml() }
        return BotContent.AutoSuggestion(choices: choices, description: description)
    }

    /// `questionText` arrives as rich-text HTML (e.g. "<p>Hey there</p>"). Kept raw/unstripped -
    /// RichTextParser renders the tags for real (bold/italic/links/lists) instead of showing them
    /// literally or discarding them.
    private func botDisplayText() -> String? {
        if let text = self["questionText"]?.contentOrNull { return text }
        if let messages = self["messages"]?.arrayValue {
            let joined = messages.compactMap { $0.contentOrNull }
            if !joined.isEmpty { return joined.joined(separator: "\n") }
        }
        return nil
    }
}

private func mediaKind(of url: String) -> BotContent.MediaKind {
    if matches(url, pattern: #"^https?://.*\.(jpg|jpeg|png|webp|jfif|gif)"#) { return .image }
    if matches(url, pattern: #"^https?://.*\.(mp4|webm|ogv)"#) { return .video }
    if matches(url, pattern: #"^https?://.*\.(mp3|wav|ogx|ogg|m4a|aac)"#) { return .audio }
    return .other
}

private func matches(_ text: String, pattern: String) -> Bool {
    text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

/// Ports `updateContent()`: replace each known variable name (word-bounded) with its value.
private func resolveVariables(_ text: String, _ variables: [String: String]) -> String {
    guard text.contains("@"), !variables.isEmpty else { return text }
    let pattern = variables.keys.map { NSRegularExpression.escapedPattern(for: $0) + "\\b" }.joined(separator: "|")
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    var result = ""
    var lastEnd = 0
    regex.enumerateMatches(in: text, range: range) { match, _, _ in
        guard let match else { return }
        result += nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
        let matched = nsText.substring(with: match.range)
        let value = variables.first { $0.key.caseInsensitiveCompare(matched) == .orderedSame }?.value ?? ""
        result += value
        lastEnd = match.range.location + match.range.length
    }
    result += nsText.substring(from: lastEnd)
    return result
}

/// `[String?]?.at(index)` -> `String?`, collapsing both "out of range" and "element itself nil"
/// into nil, matching Kotlin's `list?.getOrNull(index)` on a `List<String?>?`.
private extension Array where Element == String? {
    func at(_ index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private let variableReferencePattern = #"@[A-Za-z0-9_]+"#

/// Ports `isChoiceTextPopulated()`: hide choices whose @variables are empty/unresolved.
private func isTextPopulated(_ text: String, _ variables: [String: String]) -> Bool {
    if text.strippingHtml().isEmpty { return false }
    if text.contains("@") {
        let references = allMatches(text, pattern: variableReferencePattern)
        if references.isEmpty { return true }
        return references.allSatisfy { ref in
            let value = variables.first { $0.key.caseInsensitiveCompare(ref) == .orderedSame }?.value
            return !(value?.isEmpty ?? true)
        }
    }
    return !resolveVariables(text, variables).strippingHtml().isEmpty
}

private func allMatches(_ text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    return regex.matches(in: text, range: range).map { nsText.substring(with: $0.range) }
}

extension String {
    /// Strips tags entirely rather than rendering them - reserved for short auxiliary labels
    /// (button text, card headings/captions, populated-variable checks) that render through plain
    /// text with no rich-text support.
    func strippingHtml() -> String {
        var result = replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>\s*<p>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ports `normalizeMessageNewlines()`: LLM nodes send literal "\n" escape sequences in text.
    func normalizedNewlines() -> String {
        replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
    }
}
