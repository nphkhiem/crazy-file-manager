import SwiftUI

@main
@MainActor
struct CrazyFileManagerApp: App {
  @State private var explorerSession: ExplorerSession

  init() {
    let container = AppContainer.live()
    _explorerSession = State(initialValue: container.explorerSession)
  }

  var body: some Scene {
    WindowGroup("Crazy File Manager") {
      ExplorerView(session: explorerSession)
        .frame(
          minWidth: CFMDesign.Layout.minimumWindowWidth,
          minHeight: CFMDesign.Layout.minimumWindowHeight
        )
    }
    .defaultSize(
      width: CFMDesign.Layout.defaultWindowWidth,
      height: CFMDesign.Layout.defaultWindowHeight
    )
    .windowResizability(.contentMinSize)
  }
}
