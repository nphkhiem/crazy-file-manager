import SwiftUI

struct AmbientBackground: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)

      if !reduceTransparency {
        Circle()
          .fill(CFMDesign.Color.brand(for: colorScheme).opacity(0.20))
          .frame(width: 420, height: 420)
          .blur(radius: 64)
          .offset(x: -320, y: -210)

        Circle()
          .fill(CFMDesign.Color.ambientBlue(for: colorScheme).opacity(0.18))
          .frame(width: 460, height: 460)
          .blur(radius: 68)
          .offset(x: 350, y: 220)

        Circle()
          .fill(Color.purple.opacity(colorScheme == .dark ? 0.10 : 0.07))
          .frame(width: 300, height: 300)
          .blur(radius: 72)
          .offset(x: 260, y: -240)
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
