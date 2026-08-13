import SwiftUI

@available(iOS 13.0, *)
public enum Chat360Icon: String {
    case arrowUp = "arrow.up"
    case play = "play.fill"
    case pause = "pause.fill"
    case check = "checkmark"
    case dictate = "waveform"
    case download = "arrow.down.to.line"
    case chevronLeft = "chevron.left"
    case menu = "line.3.horizontal"
    case add = "plus"
    case star = "star.fill"
    case chevronRight = "chevron.right"
    case history = "clock.arrow.circlepath"
    case more = "ellipsis"
    case person = "person.fill"
    case training = "graduationcap.fill"
    case lightMode = "sun.max.fill"
    case darkMode = "moon.fill"
    case refresh = "arrow.clockwise"
    case shortcut = "bolt.fill"
    case attachFile = "paperclip"
    case mic = "mic.fill"
    case close = "xmark"

    public var image: Image {
        Image(systemName: rawValue)
    }
}
