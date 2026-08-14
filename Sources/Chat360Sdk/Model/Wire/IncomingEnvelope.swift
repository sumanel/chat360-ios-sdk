import Foundation

public typealias JSONObject = [String: JSONValue]

public struct RawSocketEnvelope: Codable, Equatable {
    public var user: String?
    public var type: String?
    public var data: JSONValue?
    public var message: JSONValue?
    public var chat_msg_id: String?
    public var status: String?
    public var targetId: String?
    public var error: String?
    public var stream_id: String?
    public var end_stream: Bool?
    public var update_status: Bool?
    public var auto_archival: Bool?
    public var time: String?
    public var timestamp_int: String?
    public var room_id: String?

    public init(
        user: String? = nil, type: String? = nil, data: JSONValue? = nil, message: JSONValue? = nil,
        chat_msg_id: String? = nil, status: String? = nil, targetId: String? = nil, error: String? = nil,
        stream_id: String? = nil, end_stream: Bool? = nil, update_status: Bool? = nil, auto_archival: Bool? = nil,
        time: String? = nil, timestamp_int: String? = nil, room_id: String? = nil
    ) {
        self.user = user; self.type = type; self.data = data; self.message = message
        self.chat_msg_id = chat_msg_id; self.status = status; self.targetId = targetId; self.error = error
        self.stream_id = stream_id; self.end_stream = end_stream; self.update_status = update_status
        self.auto_archival = auto_archival; self.time = time; self.timestamp_int = timestamp_int
        self.room_id = room_id
    }

    public var dataObject: JSONObject? { data?.objectValue }
}

public enum IncomingSocketEvent: Equatable {
    case pong
    case closeConnection(suppressReconnect: Bool)
    case ack(chatMsgId: String?)
    case echoedUserMessage(chatMsgId: String?, text: String?, timestampMs: Int64?)
    case typingStatus(isTyping: Bool)
    case botMessage(node: BotNode)
    case agentAssigned(agent: AssignedAgent)
    case liveChatEnded
    case inactivityNotice(message: String?, autoArchive: Bool)
    case unhandled(raw: RawSocketEnvelope)
}

extension RawSocketEnvelope {
    public func toIncomingEvent() -> IncomingSocketEvent {
        let timestampMs = timestamp_int.flatMap { Double($0) }.map { Int64($0 * 1000) } ?? time.parseServerTimestamp()

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
            return .echoedUserMessage(chatMsgId: chat_msg_id, text: message?.contentOrNull, timestampMs: timestampMs)
        }

        if type == "typing_status" {
            return .typingStatus(isTyping: status == "typing")
        }

        if update_status == true {
            return .liveChatEnded
        }

        if type == "chat_inactivity_message" {
            let isMessage = dataObject?["type"]?.contentOrNull == "message"
            let text = isMessage ? dataObject?["message"]?.contentOrNull : nil
            return .inactivityNotice(message: text, autoArchive: auto_archival == true)
        }

        if type == "validation_error" {
            let text = message?.contentOrNull.flatMap { $0.isBlank ? nil : $0 }
            return .botMessage(node: BotNode(
                nodeId: nil,
                nodeType: "validation_error",
                targetId: targetId,
                variable: nil,
                text: text,
                content: text != nil ? .plainText : .unsupported(.init(nodeType: "validation_error")),
                timestampMs: timestampMs
            ))
        }

        if let assignedUserObj = dataObject?["assigned_user"]?.objectValue, !assignedUserObj.isEmpty {
            return .agentAssigned(agent: assignedUserObj.toAssignedAgent())
        }

        if (user == "bot" || user == "admin" || user == "operator"), let data = dataObject {
            var node = data.toBotNode(fallbackTargetId: targetId)
            node.timestampMs = timestampMs
            var authored = node
            if user != "bot" {
                authored.author = .agent
            }
            if user == "bot" && (authored.nodeType?.isBlank ?? true) && type == "chatgpt_message" {
                authored.streamId = stream_id
                authored.streamEnded = end_stream ?? true
            }
            return .botMessage(node: authored)
        }

        if user == "bot" && type == "chatgpt_message" {
            let chunkText = message?.contentOrNull.map { $0.normalizedNewlines() }.flatMap { $0.isBlank ? nil : $0 }
            return .botMessage(node: BotNode(
                nodeId: nil,
                nodeType: "chatgpt_message",
                targetId: targetId,
                variable: nil,
                text: chunkText,
                content: chunkText != nil ? .plainText : .unsupported(.init(nodeType: "chatgpt_message")),
                streamId: stream_id,
                streamEnded: end_stream ?? true,
                timestampMs: timestampMs
            ))
        }

        return .unhandled(raw: self)
    }
}

extension Optional where Wrapped == String {
    func parseServerTimestamp() -> Int64? {
        guard let self else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: self) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension JSONObject {
    func toAssignedAgent() -> AssignedAgent {
        AssignedAgent(
            name: string("operator_name").flatMap { $0.isBlank ? nil : $0 },
            designation: string("user_designation").flatMap { $0.isBlank ? nil : $0 },
            avatarUrl: string("avatar").flatMap { $0.isBlank ? nil : $0 }
        )
    }

    public func toBotNode(fallbackTargetId: String? = nil) -> BotNode {
        let nodeType = string("nodeType")
        let nodeTargetId = string("targetId") ?? fallbackTargetId
        let variables = variablesMap()

        let options: [BotContent.MultiChoice.Option] = (self["buttons"]?.arrayValue ?? []).enumerated().compactMap { index, element in
            guard let button = element.objectValue, let rawText = button.string("text") else { return nil }
            guard isTextPopulated(rawText, variables) else { return nil }
            return BotContent.MultiChoice.Option(
                index: index,
                text: resolveVariables(rawText, variables).strippedHtml(),
                targetId: button.string("targetId")
            )
        }

        let rawText = botDisplayText()
        let linkUrl = nodeType == "LINK" ? string("urlMessage").map { resolveVariables($0, variables) } : nil
        var text: String? = (nodeType == "LINK" && (rawText?.isBlank ?? true)) ? linkUrl : rawText
        text = text.map { resolveVariables($0, variables).normalizedNewlines() }
        text = text.flatMap { $0.isBlank ? nil : $0 }

        let content: BotContent
        if (nodeType == "MULTI_CHOICE" || nodeType == "YES_NO") && !options.isEmpty {
            content = .multiChoice(.init(variant: string("choiceType"), options: options))
        } else if nodeType == "MEDIA" {
            content = mediaContent(variables).map { BotContent.media($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "CAROUSEL" {
            content = carouselContent(variables).map { BotContent.carousel($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "FILE_UPLOAD" {
            content = .fileUploadPrompt(fileUploadContent(variables))
        } else if nodeType == "DOWNLOAD_MEDIA" {
            content = downloadMediaContent(variables).map { BotContent.downloadMedia($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "RATING" {
            content = .rating(ratingContent())
        } else if nodeType == "FORM" {
            content = formContent(variables).map { BotContent.form($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "WINDOW_EVENT" {
            content = .windowEvent(windowEventContent(variables))
        } else if nodeType == "EMAIL" {
            content = .emailPrompt
        } else if nodeType == "PHONE" {
            content = .phonePrompt(phoneContent())
        } else if nodeType == "CUSTOMINPUT" {
            if let autoSuggestion = autoSuggestionContent(variables) {
                content = .autoSuggestion(autoSuggestion)
            } else {
                content = text != nil ? .plainText : .unsupported(.init(nodeType: nodeType))
            }
        } else if nodeType == "DATE" {
            content = .datePrompt(.init(rules: standaloneDateRules()))
        } else if nodeType == "TIME" {
            content = .timePrompt(timeContent())
        } else if nodeType == "MULTIPLE_CHECK_BOX" {
            content = multiOptionContent(variables).map { BotContent.multiOption($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "IMAGE_BUTTON" {
            content = imageButtonContent(variables).map { BotContent.imageButtons($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "TEXT_CAROUSEL" {
            content = textCarouselContent(variables).map { BotContent.textCarousel($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "LINK" {
            content = (!(rawText?.isBlank ?? true) && linkUrl != nil) ? .linkCard(.init(url: linkUrl!)) : .plainText
        } else if nodeType == "AGENT_TRANSFER" || nodeType == "TEAM_TRANSFER" {
            content = .agentTransferNotice
        } else if nodeType == "FEEDBACK" {
            content = .rating(ratingContent())
        } else if nodeType == "WELCOME_SCREEN" {
            content = welcomeScreenContent(variables).map { BotContent.welcomeScreen($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if nodeType == "IFRAME" {
            content = iframeContent(nodeTargetId: nodeTargetId).map { BotContent.iframeContent($0) } ?? .unsupported(.init(nodeType: nodeType))
        } else if text != nil {
            content = .plainText
        } else {
            content = .unsupported(.init(nodeType: nodeType))
        }

        return BotNode(
            nodeId: string("id"),
            nodeType: nodeType,
            targetId: nodeTargetId,
            variable: string("variable").flatMap { $0.isBlank ? nil : $0 },
            text: text,
            content: content,
            endUrlMessage: nodeType == "END" ? string("urlMessage").flatMap { $0.isBlank ? nil : $0 } : nil,
            endSessionRequested: nodeType == "END" && boolean("end_session")
        )
    }

    private func variablesMap() -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in self["variables"]?.objectValue ?? [:] {
            if key.isBlank || key == "@" { continue }
            result[key] = value.contentOrNull ?? ""
        }
        return result
    }

    private func mediaContent(_ variables: [String: String]) -> BotContent.Media? {
        guard let rawUrl = string("media_url") else { return nil }
        let url = resolveVariables(rawUrl, variables)
        let title = string("media_title").map { resolveVariables($0, variables) }
        let dynamicButtons: [BotContent.TextCarousel.DynamicButton] = (self["dynamic_buttons"]?.arrayValue ?? []).compactMap { entry in
            guard let b = entry.objectValue else { return nil }
            return BotContent.TextCarousel.DynamicButton(
                title: b.string("title").map { resolveVariables($0, variables) } ?? "",
                targetId: b.string("targetId").flatMap { $0.isBlank ? nil : $0 },
                componentUuid: b.string("componentUuid").flatMap { $0.isBlank ? nil : $0 }
            )
        }
        return BotContent.Media(
            url: url,
            kind: mediaKindOf(url),
            title: title,
            downloadDisabled: boolean("disable_download"),
            dynamicButtons: dynamicButtons
        )
    }

    private func carouselContent(_ variables: [String: String]) -> BotContent.Carousel? {
        guard let urlEntries = self["carousel_url"]?.arrayValue else { return nil }
        let links = self["link_carousel"]?.arrayValue?.stringsOrNull()
        let captions = self["caption_carousel"]?.arrayValue?.stringsOrNull()
        let headings = self["heading_carousel"]?.arrayValue?.stringsOrNull()

        let cards: [BotContent.Carousel.Card] = urlEntries.enumerated().compactMap { index, entry in
            guard let rawUrl = entry.arrayValue?.first?.contentOrNull else { return nil }
            return BotContent.Carousel.Card(
                imageUrl: resolveVariables(rawUrl, variables),
                heading: headings?[safe: index].flatMap { $0 }.map { resolveVariables($0, variables).strippedHtml() },
                caption: captions?[safe: index].flatMap { $0 }.map { resolveVariables($0, variables).strippedHtml() },
                link: links?[safe: index].flatMap { $0 }.map { resolveVariables($0, variables) }.flatMap { $0.isBlank ? nil : $0 }
            )
        }
        return cards.isEmpty ? nil : .init(cards: cards)
    }

    private func fileUploadContent(_ variables: [String: String]) -> BotContent.FileUploadPrompt {
        let extensionsByKey: [String: [String]] = [
            "image": ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "jfif"],
            "video": ["mp4", "webm", "mov", "ogv", "avi", "hevc", "m4v"],
            "document": ["pdf", "doc", "docx", "odt", "txt", "xlsx", "csv", "zip"],
            "audio": ["mp3", "wav", "ogg", "ogx"],
            "pdf": ["pdf"],
        ]
        var extensions: [String] = []
        for entry in self["fileType"]?.arrayValue ?? [] {
            guard let obj = entry.objectValue else { continue }
            let enabled = obj.boolean("value")
            guard let key = obj.string("key")?.lowercased(), enabled else { continue }
            extensions.append(contentsOf: extensionsByKey[key] ?? [])
        }
        var seen = Set<String>()
        extensions = extensions.filter { seen.insert($0).inserted }
        let allowed = extensions.isEmpty ? Array(Set(extensionsByKey.values.flatMap { $0 })) : extensions
        let prompt = string("questionText").map { resolveVariables($0, variables) }?.strippedHtml()
        return BotContent.FileUploadPrompt(promptText: prompt, allowedExtensions: allowed, allowCamera: boolean("enableCameraInput"))
    }

    private func downloadMediaContent(_ variables: [String: String]) -> BotContent.DownloadMedia? {
        guard let rawUrl = string("media_url") else { return nil }
        let url = resolveVariables(rawUrl, variables)
        var name = string("mediaName") ?? String(url.split(separator: "/").last ?? "")
        name = name.split(separator: "?").first.map(String.init) ?? name
        if name.isBlank { name = "download" }
        return BotContent.DownloadMedia(fileUrl: url, fileName: name)
    }

    private func ratingContent() -> BotContent.Rating {
        let style = string("rating_type") == "star_custom" ? "star" : "emoji"
        let scale = style == "star" ? (string("rating_max").flatMap { Int($0) } ?? 5) : 5
        return BotContent.Rating(style: style, scale: scale)
    }

    private func formContent(_ variables: [String: String]) -> BotContent.Form? {
        guard let elements = self["elements"]?.arrayValue else { return nil }
        let fields: [BotContent.Form.Field] = elements.enumerated().compactMap { index, element -> BotContent.Form.Field? in
            guard let obj = element.objectValue else { return nil }
            let fieldType: BotContent.Form.FieldType
            switch obj.string("type")?.uppercased() {
            case "TEXT": fieldType = .text
            case "NUMBER": fieldType = .number
            case "EMAIL": fieldType = .email
            case "PHONE": fieldType = .phone
            case "SELECT": fieldType = .select
            case "DATE": fieldType = .date
            case "MEDIA": fieldType = .media
            default: fieldType = .other
            }
            let options = (obj["options"]?.arrayValue?.stringsOrNull() ?? [])
                .compactMap { $0 }
                .map { resolveVariables($0, variables) }
            let validation = obj.fieldValidation(dateFormat: obj.string("dateFormat"))
            return BotContent.Form.Field(
                index: index,
                type: fieldType,
                label: obj.string("label").map { resolveVariables($0, variables).strippedHtml() }.flatMap { $0.isBlank ? nil : $0 },
                placeholder: obj.string("placeholder").map { resolveVariables($0, variables) },
                isRequired: (validation?.isRequired == true) || obj.boolean("isRequired"),
                options: options,
                variable: obj.string("variable").flatMap { $0.isBlank ? nil : $0 },
                validation: validation
            )
        }
        if fields.isEmpty { return nil }
        let submitText = string("submitButtonText").map { resolveVariables($0, variables) }.flatMap { $0.isBlank ? nil : $0 } ?? "Submit"
        return BotContent.Form(fields: fields, submitButtonText: submitText)
    }

    private func fieldValidation(dateFormat: String?) -> BotContent.Form.FieldValidation? {
        guard let v = self["validation"]?.objectValue else { return nil }
        var dateRules: DateRules? = nil
        if v.containsAnyDateKey() {
            dateRules = DateRules(
                isScheduledDate: v.boolean("isScheduledDate"),
                disabledDays: v["disabledDays"]?.arrayValue?.map { $0.boolValue == true },
                disabledDates: v["disableDates"]?.arrayValue?.stringsOrNull().compactMap { $0 },
                disableFuture: v.boolean("isFutureDisabled"),
                disablePrevious: v.boolean("isPrevDisabled"),
                dateFormat: dateFormat.flatMap { $0.isBlank ? nil : $0 } ?? "DD MMM YYYY"
            )
        }
        return BotContent.Form.FieldValidation(
            isRequired: v.boolean("isRequired"),
            errorMessage: v.string("errorMessage").flatMap { $0.isBlank ? nil : $0 },
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

    private func standaloneDateRules() -> DateRules {
        DateRules(
            isScheduledDate: boolean("isScheduledDate"),
            disabledDays: self["disabledDays"]?.arrayValue?.map { $0.boolValue == true },
            disabledDates: self["disabledDates"]?.arrayValue?.stringsOrNull().compactMap { $0 },
            disableFuture: boolean("isFutureDate"),
            disableCurrent: boolean("isCurrentDate"),
            disablePrevious: boolean("isPrevDate"),
            manageWithVariable: boolean("manageWithVariable"),
            variableMode: string("variableMode"),
            variableDates: string("datesVariable")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isBlank },
            dateFormat: string("dateFormat").flatMap { $0.isBlank ? nil : $0 } ?? "DD MMM YYYY"
        )
    }

    private func timeContent() -> BotContent.TimePrompt {
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
        return BotContent.TimePrompt(disabledSlots: disabled, disablePrevious: boolean("disablePrev"))
    }

    private func windowEventContent(_ variables: [String: String]) -> BotContent.WindowEvent {
        let shouldSend = self["should_send_data"]?.boolValue ?? true
        let shouldReceive = self["should_receive_data"]?.boolValue ?? false
        var sendData: [String: String] = [:]
        for (key, value) in self["send_data"]?.objectValue ?? [:] {
            guard let raw = value.contentOrNull else { continue }
            sendData[key] = resolveVariables(raw, variables)
        }
        return BotContent.WindowEvent(shouldSend: shouldSend, sendData: sendData, shouldReceive: shouldReceive)
    }

    private func phoneContent() -> BotContent.PhonePrompt {
        BotContent.PhonePrompt(
            allowInternational: boolean("allowInternationalNumber"),
            splitVariable: boolean("split_variable"),
            countryCodeVar: string("country_code_var").flatMap { $0.isBlank ? nil : $0 }
        )
    }

    private func multiOptionContent(_ variables: [String: String]) -> BotContent.MultiOption? {
        guard let choices = self["choices"]?.arrayValue else { return nil }
        let options: [BotContent.MultiOption.Option] = choices.enumerated().compactMap { index, element in
            guard let rawText = element.contentOrNull else { return nil }
            guard isTextPopulated(rawText, variables) else { return nil }
            return BotContent.MultiOption.Option(index: index, text: resolveVariables(rawText, variables).strippedHtml())
        }
        if options.isEmpty { return nil }
        let description = (string("description") ?? string("questionText"))
            .map { resolveVariables($0, variables).strippedHtml() }.flatMap { $0.isBlank ? nil : $0 }
        return BotContent.MultiOption(description: description, options: options)
    }

    private func imageButtonContent(_ variables: [String: String]) -> BotContent.ImageButtons? {
        guard let urlEntries = self["carousel_url"]?.arrayValue else { return nil }
        let descriptions = self["link_carousel"]?.arrayValue?.stringsOrNull()
        let flatButtons = self["buttons"]?.arrayValue?.compactMap { $0.objectValue } ?? []

        var perSlideButtons: [[RawImageButton]] = []
        if let imgButtons = self["img_buttons"]?.arrayValue {
            perSlideButtons = imgButtons.map { slide in
                (slide.arrayValue ?? []).compactMap { entry -> RawImageButton? in
                    guard let obj = entry.objectValue else { return nil }
                    return RawImageButton(text: obj.string("text") ?? "", type: obj.string("type") ?? "reply", value: obj.string("value"), url: obj.string("url"))
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
            let buttons = (perSlideButtons[safe: index] ?? []).map { raw -> BotContent.ImageButtons.Button in
                let targetId = flatButtons[safe: flatIndex].flatMap { $0.string("targetId") }
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
                description: descriptions?[safe: index].flatMap { $0 }.map { resolveVariables($0, variables).strippedHtml() },
                buttons: buttons
            )
        }
        if cards.isEmpty { return nil }
        return BotContent.ImageButtons(cards: cards, submitType: string("submit_type") ?? "BUTTON")
    }

    private func textCarouselContent(_ variables: [String: String]) -> BotContent.TextCarousel? {
        guard let rawCards = self["text_cards"]?.arrayValue else { return nil }
        let isType2 = string("text_carousel_type") == "type2"
        let cards: [BotContent.TextCarousel.Card] = rawCards.compactMap { entry in
            guard let obj = entry.objectValue else { return nil }
            let content = obj.string("content").map { resolveVariables($0, variables) }?.strippedHtml()
            if !isType2 && (content?.isBlank ?? true) { return nil }
            let ctaButtons: [BotContent.TextCarousel.CtaButton] = (obj["ctaButtons"]?.arrayValue ?? []).compactMap { btn in
                guard let b = btn.objectValue else { return nil }
                return BotContent.TextCarousel.CtaButton(
                    name: b.string("name").map { resolveVariables($0, variables) } ?? "",
                    type: b.string("type") == "component_uuid" ? "component_uuid" : "link",
                    link: b.string("link") ?? ""
                )
            }
            let buttons: [BotContent.TextCarousel.CardButton] = (obj["buttons"]?.arrayValue ?? []).compactMap { btn in
                guard let b = btn.objectValue else { return nil }
                return BotContent.TextCarousel.CardButton(
                    label: b.string("label").map { resolveVariables($0, variables) } ?? "",
                    link: b.string("link")
                )
            }
            return BotContent.TextCarousel.Card(
                name: obj.string("name").flatMap { $0.isBlank ? nil : $0 },
                content: content,
                bgColor: obj.string("bgColor"),
                bgImage: obj.string("bgImage").flatMap { $0.isBlank ? nil : $0 },
                footerText: obj.string("footerText").map { resolveVariables($0, variables) },
                iconText: obj.string("iconText").map { resolveVariables($0, variables) },
                iconUrl: obj.string("iconUrl").flatMap { $0.isBlank ? nil : $0 },
                redirectType: obj.string("redirectType").flatMap { $0.isBlank ? nil : $0 },
                redirectLink: obj.string("redirectLink").flatMap { $0.isBlank ? nil : $0 },
                ctaButtons: ctaButtons,
                buttons: buttons
            )
        }
        if cards.isEmpty { return nil }
        let dynamicButtons: [BotContent.TextCarousel.DynamicButton] = (self["dynamic_buttons"]?.arrayValue ?? []).compactMap { btn in
            guard let b = btn.objectValue else { return nil }
            return BotContent.TextCarousel.DynamicButton(
                title: b.string("title").map { resolveVariables($0, variables) } ?? "",
                targetId: b.string("targetId").flatMap { $0.isBlank ? nil : $0 },
                componentUuid: b.string("componentUuid").flatMap { $0.isBlank ? nil : $0 }
            )
        }
        return BotContent.TextCarousel(cards: cards, dynamicButtons: dynamicButtons)
    }

    private func iframeContent(nodeTargetId: String?) -> BotContent.IframeContent? {
        guard let src = string("src"), !src.isBlank else { return nil }
        return BotContent.IframeContent(
            url: src,
            heightDp: int("height"),
            moveForEvent: string("moveForEvent").flatMap { $0.isBlank ? nil : $0 },
            targetId: nodeTargetId
        )
    }

    private func welcomeScreenContent(_ variables: [String: String]) -> BotContent.WelcomeScreen? {
        let cards: [BotContent.WelcomeScreen.Card] = (self["text_cards"]?.arrayValue ?? []).compactMap { entry in
            guard let obj = entry.objectValue else { return nil }
            return BotContent.WelcomeScreen.Card(
                name: obj.string("name").map { resolveVariables($0, variables) },
                title: obj.string("title").map { resolveVariables($0, variables) },
                bgColor: obj.string("bgColor"),
                bgImageUrl: obj.string("bgImageUrl").flatMap { $0.isBlank ? nil : $0 },
                ctaEnabled: obj.boolean("ctaEnabled"),
                ctaType: obj.string("ctaType") ?? "external_link",
                ctaLink: obj.string("ctaLink").flatMap { $0.isBlank ? nil : $0 }
            )
        }
        let title = string("title").map { resolveVariables($0, variables) }
        let description = string("description").map { resolveVariables($0, variables) }
        if cards.isEmpty && (title?.isBlank ?? true) && (description?.isBlank ?? true) { return nil }
        return BotContent.WelcomeScreen(
            iconUrl: string("mainIconUrl").flatMap { $0.isBlank ? nil : $0 },
            title: title,
            description: description,
            cards: cards
        )
    }

    private func autoSuggestionContent(_ variables: [String: String]) -> BotContent.AutoSuggestion? {
        let type = self["dataType"]?.objectValue?.string("type")
        guard type == "AUTOSUGGESTION" else { return nil }
        guard let raw = string("autoSuggestionOptions") else { return nil }
        let choices = raw.components(separatedBy: "{&}").map { resolveVariables($0, variables).trimmingCharacters(in: .whitespaces) }.filter { !$0.isBlank }
        if choices.isEmpty { return nil }
        let description = string("autoSuggestionDescription").map { resolveVariables($0, variables) }?.strippedHtml()
        return BotContent.AutoSuggestion(choices: choices, description: description)
    }

    private func botDisplayText() -> String? {
        if let text = self["questionText"]?.contentOrNull { return text }
        if let messages = self["messages"]?.arrayValue {
            let joined = messages.compactMap { $0.contentOrNull }
            if !joined.isEmpty { return joined.joined(separator: "\n") }
        }
        return nil
    }

    func string(_ key: String) -> String? { self[key]?.contentOrNull }
    func boolean(_ key: String) -> Bool { self[key]?.boolValue ?? (self[key]?.contentOrNull == "1") }
    func int(_ key: String) -> Int? { self[key]?.doubleValue.map { Int($0) } }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func containsKey(_ key: String) -> Bool { self[key] != nil }
}

private func resolveVariables(_ text: String, _ variables: [String: String]) -> String {
    guard text.contains("@"), !variables.isEmpty else { return text }
    let pattern = variables.keys.map { NSRegularExpression.escapedPattern(for: $0) + "\\b" }.joined(separator: "|")
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
    let nsText = text as NSString
    var result = ""
    var lastIndex = 0
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    for match in matches {
        result += nsText.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex))
        let matchedValue = nsText.substring(with: match.range)
        let replacement = variables.first { $0.key.caseInsensitiveCompare(matchedValue) == .orderedSame }?.value ?? ""
        result += replacement
        lastIndex = match.range.location + match.range.length
    }
    result += nsText.substring(from: lastIndex)
    return result
}

private let variableReferenceRegex = try! NSRegularExpression(pattern: "@[A-Za-z0-9_]+")

private func isTextPopulated(_ text: String, _ variables: [String: String]) -> Bool {
    if text.strippedHtml().isBlank { return false }
    if text.contains("@") {
        let nsText = text as NSString
        let matches = variableReferenceRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let references = matches.map { nsText.substring(with: $0.range) }
        if references.isEmpty { return true }
        return references.allSatisfy { ref in
            !(variables.first { $0.key.caseInsensitiveCompare(ref) == .orderedSame }?.value ?? "").isBlank
        }
    }
    return !resolveVariables(text, variables).strippedHtml().isBlank
}

private func mediaKindOf(_ url: String) -> BotContent.MediaKind {
    if url.range(of: "^https?://.*\\.(jpg|jpeg|png|webp|jfif|gif)", options: [.regularExpression, .caseInsensitive]) != nil {
        return .image
    }
    if url.range(of: "^https?://.*\\.(mp4|webm|ogv)", options: [.regularExpression, .caseInsensitive]) != nil {
        return .video
    }
    if url.range(of: "^https?://.*\\.(mp3|wav|ogx|ogg|m4a|aac)", options: [.regularExpression, .caseInsensitive]) != nil {
        return .audio
    }
    return .other
}

private struct RawImageButton {
    let text: String
    let type: String
    let value: String?
    let url: String?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == JSONValue {
    func stringsOrNull() -> [String?] { map { $0.contentOrNull } }
}

extension String {
    func strippedHtml() -> String {
        var result = replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>\\s*<p>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedNewlines() -> String {
        replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
    }
}
