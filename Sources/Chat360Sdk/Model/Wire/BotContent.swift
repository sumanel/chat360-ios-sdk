import Foundation

public struct BotNode: Equatable {
    public enum MessageAuthor { case bot, agent }

    public var nodeId: String?
    public var nodeType: String?
    public var targetId: String?
    public var variable: String?
    public var text: String?
    public var content: BotContent
    public var endUrlMessage: String?
    public var endSessionRequested: Bool = false
    public var streamId: String?
    public var streamEnded: Bool = true
    public var author: MessageAuthor = .bot
    public var timestampMs: Int64?

    public init(
        nodeId: String?,
        nodeType: String?,
        targetId: String?,
        variable: String?,
        text: String?,
        content: BotContent,
        endUrlMessage: String? = nil,
        endSessionRequested: Bool = false,
        streamId: String? = nil,
        streamEnded: Bool = true,
        author: MessageAuthor = .bot,
        timestampMs: Int64? = nil
    ) {
        self.nodeId = nodeId
        self.nodeType = nodeType
        self.targetId = targetId
        self.variable = variable
        self.text = text
        self.content = content
        self.endUrlMessage = endUrlMessage
        self.endSessionRequested = endSessionRequested
        self.streamId = streamId
        self.streamEnded = streamEnded
        self.author = author
        self.timestampMs = timestampMs
    }
}

public indirect enum BotContent: Equatable {
    case plainText
    case multiChoice(MultiChoice)
    case media(Media)
    case carousel(Carousel)
    case fileUploadPrompt(FileUploadPrompt)
    case downloadMedia(DownloadMedia)
    case rating(Rating)
    case form(Form)
    case windowEvent(WindowEvent)
    case emailPrompt
    case phonePrompt(PhonePrompt)
    case autoSuggestion(AutoSuggestion)
    case datePrompt(DatePrompt)
    case timePrompt(TimePrompt)
    case multiOption(MultiOption)
    case imageButtons(ImageButtons)
    case textCarousel(TextCarousel)
    case linkCard(LinkCard)
    case agentTransferNotice
    case welcomeScreen(WelcomeScreen)
    case iframeContent(IframeContent)
    case unsupported(Unsupported)
}

extension BotContent {
    public struct MultiChoice: Equatable {
        public struct Option: Equatable {
            public let index: Int
            public let text: String
            public let targetId: String?
            public init(index: Int, text: String, targetId: String?) {
                self.index = index; self.text = text; self.targetId = targetId
            }
        }
        public let variant: String?
        public let options: [Option]
        public init(variant: String?, options: [Option]) {
            self.variant = variant; self.options = options
        }
    }

    public enum MediaKind { case image, video, audio, other }

    public struct Media: Equatable {
        public let url: String
        public let kind: MediaKind
        public let title: String?
        public let downloadDisabled: Bool
        public let dynamicButtons: [TextCarousel.DynamicButton]
        public init(url: String, kind: MediaKind, title: String?, downloadDisabled: Bool, dynamicButtons: [TextCarousel.DynamicButton] = []) {
            self.url = url; self.kind = kind; self.title = title
            self.downloadDisabled = downloadDisabled; self.dynamicButtons = dynamicButtons
        }
    }

    public struct Carousel: Equatable {
        public struct Card: Equatable {
            public let imageUrl: String
            public let heading: String?
            public let caption: String?
            public let link: String?
            public init(imageUrl: String, heading: String?, caption: String?, link: String?) {
                self.imageUrl = imageUrl; self.heading = heading; self.caption = caption; self.link = link
            }
        }
        public let cards: [Card]
        public init(cards: [Card]) { self.cards = cards }
    }

    public struct FileUploadPrompt: Equatable {
        public let promptText: String?
        public let allowedExtensions: [String]
        public let allowCamera: Bool
        public init(promptText: String?, allowedExtensions: [String], allowCamera: Bool = false) {
            self.promptText = promptText; self.allowedExtensions = allowedExtensions; self.allowCamera = allowCamera
        }
    }

    public struct DownloadMedia: Equatable {
        public let fileUrl: String
        public let fileName: String
        public init(fileUrl: String, fileName: String) { self.fileUrl = fileUrl; self.fileName = fileName }
    }

    public struct Rating: Equatable {
        public let style: String
        public let scale: Int
        public init(style: String, scale: Int) { self.style = style; self.scale = scale }
    }

    public struct Form: Equatable {
        public enum FieldType { case text, number, email, phone, select, date, media, other }

        public struct FieldValidation: Equatable {
            public var isRequired: Bool = false
            public var errorMessage: String?
            public var userInputType: String?
            public var maxCharacters: Int?
            public var minCharacters: Int?
            public var email: Bool = false
            public var maxCount: Double?
            public var minCount: Double?
            public var phone: Bool = false
            public var allowInternationalNumber: Bool = false
            public var numberFormat: String?
            public var dateRules: DateRules?
            public init(
                isRequired: Bool = false, errorMessage: String? = nil, userInputType: String? = nil,
                maxCharacters: Int? = nil, minCharacters: Int? = nil, email: Bool = false,
                maxCount: Double? = nil, minCount: Double? = nil, phone: Bool = false,
                allowInternationalNumber: Bool = false, numberFormat: String? = nil, dateRules: DateRules? = nil
            ) {
                self.isRequired = isRequired; self.errorMessage = errorMessage; self.userInputType = userInputType
                self.maxCharacters = maxCharacters; self.minCharacters = minCharacters; self.email = email
                self.maxCount = maxCount; self.minCount = minCount; self.phone = phone
                self.allowInternationalNumber = allowInternationalNumber; self.numberFormat = numberFormat
                self.dateRules = dateRules
            }
        }

        public struct Field: Equatable {
            public let index: Int
            public let type: FieldType
            public let label: String?
            public let placeholder: String?
            public let isRequired: Bool
            public let options: [String]
            public let variable: String?
            public let validation: FieldValidation?
            public init(
                index: Int, type: FieldType, label: String?, placeholder: String?, isRequired: Bool,
                options: [String], variable: String?, validation: FieldValidation? = nil
            ) {
                self.index = index; self.type = type; self.label = label; self.placeholder = placeholder
                self.isRequired = isRequired; self.options = options; self.variable = variable
                self.validation = validation
            }
        }

        public let fields: [Field]
        public let submitButtonText: String
        public init(fields: [Field], submitButtonText: String) {
            self.fields = fields; self.submitButtonText = submitButtonText
        }
    }

    public struct WindowEvent: Equatable {
        public let shouldSend: Bool
        public let sendData: [String: String]
        public let shouldReceive: Bool
        public init(shouldSend: Bool, sendData: [String: String], shouldReceive: Bool) {
            self.shouldSend = shouldSend; self.sendData = sendData; self.shouldReceive = shouldReceive
        }
    }

    public struct PhonePrompt: Equatable {
        public let allowInternational: Bool
        public let splitVariable: Bool
        public let countryCodeVar: String?
        public init(allowInternational: Bool, splitVariable: Bool, countryCodeVar: String?) {
            self.allowInternational = allowInternational; self.splitVariable = splitVariable
            self.countryCodeVar = countryCodeVar
        }
    }

    public struct AutoSuggestion: Equatable {
        public let choices: [String]
        public let description: String?
        public init(choices: [String], description: String?) { self.choices = choices; self.description = description }
    }

    public struct DatePrompt: Equatable {
        public let rules: DateRules
        public init(rules: DateRules) { self.rules = rules }
    }

    public struct TimePrompt: Equatable {
        public let disabledSlots: [Int: [Int]]
        public let disablePrevious: Bool
        public init(disabledSlots: [Int: [Int]], disablePrevious: Bool) {
            self.disabledSlots = disabledSlots; self.disablePrevious = disablePrevious
        }
    }

    public struct MultiOption: Equatable {
        public struct Option: Equatable {
            public let index: Int
            public let text: String
            public init(index: Int, text: String) { self.index = index; self.text = text }
        }
        public let description: String?
        public let options: [Option]
        public init(description: String?, options: [Option]) { self.description = description; self.options = options }
    }

    public struct ImageButtons: Equatable {
        public struct Button: Equatable {
            public let text: String
            public let type: String
            public let value: String?
            public let url: String?
            public let targetId: String?
            public init(text: String, type: String, value: String?, url: String?, targetId: String?) {
                self.text = text; self.type = type; self.value = value; self.url = url; self.targetId = targetId
            }
        }
        public struct Card: Equatable {
            public let imageUrl: String
            public let description: String?
            public let buttons: [Button]
            public init(imageUrl: String, description: String?, buttons: [Button]) {
                self.imageUrl = imageUrl; self.description = description; self.buttons = buttons
            }
        }
        public let cards: [Card]
        public let submitType: String
        public init(cards: [Card], submitType: String) { self.cards = cards; self.submitType = submitType }
    }

    public struct TextCarousel: Equatable {
        public struct CtaButton: Equatable {
            public let name: String
            public let type: String
            public let link: String
            public init(name: String, type: String, link: String) { self.name = name; self.type = type; self.link = link }
        }
        public struct CardButton: Equatable {
            public let label: String
            public let link: String?
            public init(label: String, link: String?) { self.label = label; self.link = link }
        }
        public struct DynamicButton: Equatable {
            public let title: String
            public let targetId: String?
            public let componentUuid: String?
            public init(title: String, targetId: String?, componentUuid: String?) {
                self.title = title; self.targetId = targetId; self.componentUuid = componentUuid
            }
        }
        public struct Card: Equatable {
            public let name: String?
            public let content: String?
            public let bgColor: String?
            public let bgImage: String?
            public let footerText: String?
            public let iconText: String?
            public let iconUrl: String?
            public let redirectType: String?
            public let redirectLink: String?
            public let ctaButtons: [CtaButton]
            public let buttons: [CardButton]
            public init(
                name: String?, content: String?, bgColor: String?, bgImage: String?, footerText: String?,
                iconText: String?, iconUrl: String?, redirectType: String?, redirectLink: String?,
                ctaButtons: [CtaButton], buttons: [CardButton]
            ) {
                self.name = name; self.content = content; self.bgColor = bgColor; self.bgImage = bgImage
                self.footerText = footerText; self.iconText = iconText; self.iconUrl = iconUrl
                self.redirectType = redirectType; self.redirectLink = redirectLink
                self.ctaButtons = ctaButtons; self.buttons = buttons
            }
        }
        public let cards: [Card]
        public let dynamicButtons: [DynamicButton]
        public init(cards: [Card], dynamicButtons: [DynamicButton]) {
            self.cards = cards; self.dynamicButtons = dynamicButtons
        }
    }

    public struct LinkCard: Equatable {
        public let url: String
        public init(url: String) { self.url = url }
    }

    public struct WelcomeScreen: Equatable {
        public struct Card: Equatable {
            public let name: String?
            public let title: String?
            public let bgColor: String?
            public let bgImageUrl: String?
            public let ctaEnabled: Bool
            public let ctaType: String?
            public let ctaLink: String?
            public init(name: String?, title: String?, bgColor: String?, bgImageUrl: String?, ctaEnabled: Bool, ctaType: String?, ctaLink: String?) {
                self.name = name; self.title = title; self.bgColor = bgColor; self.bgImageUrl = bgImageUrl
                self.ctaEnabled = ctaEnabled; self.ctaType = ctaType; self.ctaLink = ctaLink
            }
        }
        public let iconUrl: String?
        public let title: String?
        public let description: String?
        public let cards: [Card]
        public init(iconUrl: String?, title: String?, description: String?, cards: [Card]) {
            self.iconUrl = iconUrl; self.title = title; self.description = description; self.cards = cards
        }
    }

    public struct IframeContent: Equatable {
        public let url: String
        public let heightDp: Int?
        public let moveForEvent: String?
        public let targetId: String?
        public init(url: String, heightDp: Int?, moveForEvent: String?, targetId: String?) {
            self.url = url; self.heightDp = heightDp; self.moveForEvent = moveForEvent; self.targetId = targetId
        }
    }

    public struct Unsupported: Equatable {
        public let nodeType: String?
        public init(nodeType: String?) { self.nodeType = nodeType }
    }
}
