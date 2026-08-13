import SwiftUI

@available(iOS 13.0, *)
public enum Chat360FontFamily: Equatable {
    case system
    case custom(String)

    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .custom(let name): return .custom(name, size: size)
        }
    }
}

@available(iOS 13.0, *)
public struct Chat360Typography: Equatable {
    public var headFamily: Chat360FontFamily
    public var textFamily: Chat360FontFamily

    public init(headFamily: Chat360FontFamily, textFamily: Chat360FontFamily) {
        self.headFamily = headFamily
        self.textFamily = textFamily
    }
}

@available(iOS 13.0, *)
public let defaultChat360Typography = Chat360Typography(headFamily: .system, textFamily: .system)

@available(iOS 13.0, *)
public struct Chat360TypographyKey: EnvironmentKey {
    public static let defaultValue: Chat360Typography = defaultChat360Typography
}

@available(iOS 13.0, *)
extension EnvironmentValues {
    public var chat360Typography: Chat360Typography {
        get { self[Chat360TypographyKey.self] }
        set { self[Chat360TypographyKey.self] = newValue }
    }
}
