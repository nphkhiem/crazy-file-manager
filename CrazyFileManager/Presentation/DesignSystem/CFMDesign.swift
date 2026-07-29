import SwiftUI

enum CFMDesign {
  enum Layout {
    static let defaultWindowWidth: CGFloat = 1_180
    static let defaultWindowHeight: CGFloat = 760
    static let minimumWindowWidth: CGFloat = 900
    static let minimumWindowHeight: CGFloat = 600
    static let welcomeCardWidth: CGFloat = 640
  }

  enum Spacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 16
    static let comfortable: CGFloat = 24
    static let spacious: CGFloat = 32
    static let section: CGFloat = 48
  }

  enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
  }

  enum Color {
    static func brand(for colorScheme: ColorScheme) -> SwiftUI.Color {
      switch colorScheme {
      case .dark:
        SwiftUI.Color(red: 117 / 255, green: 188 / 255, blue: 181 / 255)
      default:
        SwiftUI.Color(red: 47 / 255, green: 118 / 255, blue: 111 / 255)
      }
    }

    static func ambientBlue(for colorScheme: ColorScheme) -> SwiftUI.Color {
      switch colorScheme {
      case .dark:
        SwiftUI.Color(red: 102 / 255, green: 170 / 255, blue: 234 / 255)
      default:
        SwiftUI.Color(red: 47 / 255, green: 115 / 255, blue: 173 / 255)
      }
    }
  }
}
