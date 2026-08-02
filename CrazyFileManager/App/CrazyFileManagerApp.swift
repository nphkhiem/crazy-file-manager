import SwiftUI

@main
@MainActor
struct CrazyFileManagerApp: App {
  @NSApplicationDelegateAdaptor(ApplicationTerminationController.self)
  private var terminationController
  @State private var explorerSession: ExplorerSession
  private let customScopeChooser: any CustomScopeChoosing
  private let systemSettingsOpener: any SystemSettingsOpening

  init() {
    let container = AppContainer.live(
      arguments: ProcessInfo.processInfo.arguments
    )
    _explorerSession = State(initialValue: container.explorerSession)
    customScopeChooser = container.customScopeChooser
    systemSettingsOpener = container.systemSettingsOpener
    terminationController.session = container.explorerSession
  }

  var body: some Scene {
    WindowGroup("Crazy File Manager") {
      ExplorerView(
        session: explorerSession,
        customScopeChooser: customScopeChooser,
        systemSettingsOpener: systemSettingsOpener,
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
