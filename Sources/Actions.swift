// Built-in actions. To add one: add a case here with a title and a default
// shortcut, then give it a position in unitRect(for:) in Geometry.swift.

import AppKit

enum Action: String, CaseIterable {
    case tileAll
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, center, restore
    case nextDisplay, prevDisplay, focusNextDisplay

    var title: String {
        switch self {
        case .tileAll: return "Tile All Windows"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Walk Right"
        case .prevDisplay: return "Walk Left"
        case .focusNextDisplay: return "Jump to Next Display"
        }
    }

    /// Default shortcut, matching Rectangle's defaults. Users override these in the config's `shortcuts`.
    var defaultShortcut: String {
        switch self {
        case .tileAll: return "ctrl+alt+a"
        case .leftHalf: return "ctrl+alt+left"
        case .rightHalf: return "ctrl+alt+right"
        case .topHalf: return "ctrl+alt+up"
        case .bottomHalf: return "ctrl+alt+down"
        case .topLeft: return "ctrl+alt+u"
        case .topRight: return "ctrl+alt+i"
        case .bottomLeft: return "ctrl+alt+j"
        case .bottomRight: return "ctrl+alt+k"
        case .firstThird: return "ctrl+alt+d"
        case .centerThird: return "ctrl+alt+f"
        case .lastThird: return "ctrl+alt+g"
        case .firstTwoThirds: return "ctrl+alt+e"
        case .lastTwoThirds: return "ctrl+alt+t"
        case .maximize: return "ctrl+alt+return"
        case .almostMaximize: return "ctrl+alt+m"
        case .center: return "ctrl+alt+c"
        case .restore: return "ctrl+alt+delete"
        case .nextDisplay: return "ctrl+alt+cmd+right"
        case .prevDisplay: return "ctrl+alt+cmd+left"
        case .focusNextDisplay: return "ctrl+alt+cmd+up"
        }
    }

    /// Grouping in the menu
    static let groups: [[Action]] = [
        [.tileAll],
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
        [.maximize, .almostMaximize, .center, .restore],
        [.nextDisplay, .prevDisplay, .focusNextDisplay],
    ]

    /// Regions (unit rects) to fill in the small layout icon
    var glyphUnits: [CGRect] {
        switch self {
        case .tileAll:
            return [CGRect(x: 0, y: 0, width: 0.46, height: 0.44), CGRect(x: 0.54, y: 0, width: 0.46, height: 0.44),
                    CGRect(x: 0, y: 0.56, width: 0.46, height: 0.44), CGRect(x: 0.54, y: 0.56, width: 0.46, height: 0.44)]
        case .center: return [CGRect(x: 0.25, y: 0.22, width: 0.5, height: 0.56)]
        case .restore: return [CGRect(x: 0.15, y: 0.2, width: 0.45, height: 0.5)]
        case .nextDisplay: return [CGRect(x: 0.6, y: 0, width: 0.4, height: 1)]
        case .prevDisplay: return [CGRect(x: 0, y: 0, width: 0.4, height: 1)]
        case .focusNextDisplay: return [CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4)]
        default: return unitRect(for: self).map { [$0] } ?? []
        }
    }
}
