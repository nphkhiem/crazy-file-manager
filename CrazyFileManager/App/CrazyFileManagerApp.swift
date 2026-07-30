import SwiftUI

@main
@MainActor
struct CrazyFileManagerApp: App {
  @NSApplicationDelegateAdaptor(ApplicationTerminationController.self)
  private var terminationController
  @State private var explorerSession: ExplorerSession

  init() {
    let container = AppContainer.live()
    _explorerSession = State(initialValue: container.explorerSession)
    terminationController.session = container.explorerSession
  }

  var body: some Scene {
    WindowGroup("Crazy File Manager") {
      ExplorerView(
        session: explorerSession,
        onConfirmedQuit: {
          terminationController.completeConfirmedTermination()
        }
      )
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
