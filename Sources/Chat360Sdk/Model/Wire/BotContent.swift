import Foundation

/// A bot flow node received over the socket, with just enough context to answer it.
public struct BotNode: Equatable {
    public enum MessageAuthor: Equatable { case bot, agent }

    public var nodeId: String?
    public var nodeType: String?
    public var targetId: String?
    public var variable: String?
    public var text: String?
    public var content: BotContent
    /// END-node side effects (open externally / close the session) - not about rendering at all.
    public var endUrlMessage: String?
    public var endSessionRequested: Bool = false
    /// Set only for a chatgpt_message streaming chunk - chunks sharing an id get concatenated onto one bubble.
    public var streamId: String?
    public var streamEnded: Bool = true
    /// `.bot` for a `user:'bot'` frame, `.agent` for `user:'admin'|'operator'` - same content shapes either way.
    public var author: MessageAuthor = .bot

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
        author: MessageAuthor = .bot
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
    }
}

/// Renderable content variants. Node types without a dedicated case fall through to
/// `.unsupported` so every `switch` over this type stays exhaustive and later additions don't
/// break existing code.
public enum BotContent: Equatable {
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
    case unsupported(nodeType: String?)

    public struct MultiChoice: Equatable {
        public struct Option: Equatable {
            public var index: Int
            public var text: String
            public var targetId: String?
        }
        public var variant: String?
        public var options: [Option]
    }

    public enum MediaKind: Equatable { case image, video, audio, other }

    public struct Media: Equatable {
        public var url: String
        public var kind: MediaKind
        public var title: String?
        public var downloadDisabled: Bool
        /// Quick-reply pills rendered below the media bubble, each answering with the same
        /// "carousel-text-reply" wire shape as a TextCarousel card tap.
        public var dynamicButtons: [TextCarousel.DynamicButton] = []
    }

    public struct Carousel: Equatable {
        public struct Card: Equatable {
            public var imageUrl: String
            public var heading: String?
            public var caption: String?
            public var link: String?
        }
        public var cards: [Card]
    }

    public struct FileUploadPrompt: Equatable {
        public var promptText: String?
        public var allowedExtensions: [String]
        public var allowCamera: Bool = false
    }

    public struct DownloadMedia: Equatable {
        public var fileUrl: String
        public var fileName: String
    }

    /// style: "star" | "emoji"; scale is the star count.
    public struct Rating: Equatable {
        public var style: String
        public var scale: Int
    }

    public struct Form: Equatable {
        public enum FieldType: Equatable { case text, number, email, phone, select, date, media, other }

        public struct Field: Equatable {
            public var index: Int
            public var type: FieldType
            public var label: String?
            public var placeholder: String?
            public var isRequired: Bool
            public var options: [String]
            public var variable: String?
            public var validation: FieldValidation?
        }

        /// The exact rule set `FormFieldValidator` enforces. All-nullable/false defaults so a
        /// field with no `validation` key at all behaves exactly like before.
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
        }

        public var fields: [Field]
        public var submitButtonText: String
    }

    /// A WINDOW_EVENT node - renders nothing visually, it only triggers the host-app bridge.
    /// See `WindowEventBridge`.
    public struct WindowEvent: Equatable {
        public var shouldSend: Bool
        public var sendData: [String: String]
        public var shouldReceive: Bool
    }

    /// A PHONE node. `allowInternational == false` (the common case) means no dedicated widget or
    /// validation at all - answered through the plain free-text input. `splitVariable`/
    /// `countryCodeVar` only matter when international.
    public struct PhonePrompt: Equatable {
        public var allowInternational: Bool
        public var splitVariable: Bool
        public var countryCodeVar: String?
    }

    /// The AUTOSUGGESTION sub-variant of CUSTOMINPUT: pick one choice from a searchable list.
    public struct AutoSuggestion: Equatable {
        public var choices: [String]
        public var description: String?
    }

    /// A standalone DATE node - full rule engine, see `DateRules`.
    public struct DatePrompt: Equatable {
        public var rules: DateRules
    }

    /// A standalone TIME node. `disabledSlots` maps hour (1-12) -> the disabled minutes within it.
    public struct TimePrompt: Equatable {
        public var disabledSlots: [Int: [Int]]
        public var disablePrevious: Bool
    }

    /// A MULTIPLE_CHECK_BOX node - unlike MultiChoice, more than one option can be selected.
    public struct MultiOption: Equatable {
        public struct Option: Equatable {
            public var index: Int
            public var text: String
        }
        public var description: String?
        public var options: [Option]
    }

    /// An IMAGE_BUTTON node - visually a carousel (reuses the same card shape as `Carousel`) but
    /// each card carries its own reply/web_url buttons instead of a single tap-through link.
    public struct ImageButtons: Equatable {
        public struct Button: Equatable {
            public var text: String
            public var type: String
            public var value: String?
            public var url: String?
            public var targetId: String?
        }
        public struct Card: Equatable {
            public var imageUrl: String
            public var description: String?
            public var buttons: [Button]
        }
        public var cards: [Card]
        public var submitType: String
    }

    /// A TEXT_CAROUSEL node. Ports both wire generations (`type1`/`type2`) into one card shape
    /// rather than two distinct layouts - a deliberate simplification; per-button custom styling
    /// is not ported, cards use the theme's own button styling instead.
    public struct TextCarousel: Equatable {
        /// type "link" opens `link` externally; "component_uuid" submits `link` as a targetId.
        public struct CtaButton: Equatable {
            public var name: String
            public var type: String
            public var link: String
        }
        public struct CardButton: Equatable {
            public var label: String
            public var link: String?
        }
        public struct DynamicButton: Equatable {
            public var title: String
            public var targetId: String?
            public var componentUuid: String?
        }
        public struct Card: Equatable {
            public var name: String?
            public var content: String?
            public var bgColor: String?
            public var bgImage: String?
            public var footerText: String?
            public var iconText: String?
            public var iconUrl: String?
            /// Whole-card tap target: type "link" opens `redirectLink` externally, "component_uuid" submits it as a targetId.
            public var redirectType: String?
            public var redirectLink: String?
            public var ctaButtons: [CtaButton]
            public var buttons: [CardButton]
        }
        public var cards: [Card]
        public var dynamicButtons: [DynamicButton]
    }

    /// A LINK node that also has its own separate question text.
    public struct LinkCard: Equatable {
        public var url: String
    }

    /// A WELCOME_SCREEN node. `Card.ctaEnabled` + `ctaType == "external_link"` opens `Card.ctaLink`
    /// externally (and still submits); `ctaType == "component"` submits with `Card.ctaLink` as the
    /// targetId instead of the node's own; the outgoing text is `Card.name` trimmed, falling back
    /// to "Card {n}" (1-based).
    public struct WelcomeScreen: Equatable {
        public struct Card: Equatable {
            public var name: String?
            public var title: String?
            public var bgColor: String?
            public var bgImageUrl: String?
            public var ctaEnabled: Bool
            public var ctaType: String?
            public var ctaLink: String?
        }
        public var iconUrl: String?
        public var title: String?
        public var description: String?
        public var cards: [Card]
    }

    /// An IFRAME node. When `moveForEvent` is set, a `postMessage` from the embedded page whose
    /// `data.type === moveForEvent` (origin-checked against `url`) jumps the bot flow to `targetId`.
    public struct IframeContent: Equatable {
        public var url: String
        public var heightDp: Int?
        public var moveForEvent: String?
        public var targetId: String?
    }
}
