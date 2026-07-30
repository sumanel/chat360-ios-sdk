import Foundation

/// The two font roles every component reads through `\.chat360Typography` - never a font name
/// directly. `nil` means "use the platform system font" (SwiftUI's analog of Compose's
/// `FontFamily.SansSerif` default, since SwiftUI has no standalone "font family" type - a family
/// only becomes concrete once paired with a size via `Font.custom(_:size:)`).
public struct Chat360Typography: Equatable {
    public var headFontName: String?
    public var textFontName: String?

    public init(headFontName: String? = nil, textFontName: String? = nil) {
        self.headFontName = headFontName
        self.textFontName = textFontName
    }
}

/// The library's own default: the platform's system sans-serif, no bundled font files required.
public let DefaultChat360Typography = Chat360Typography()
