import SwiftUI

struct ExplorerView: View {
  @Environment(\.scenePhase) private var scenePhase

  let session: ExplorerSession
  let customScopeChooser: any CustomScopeChoosing
  let systemSettingsOpener: any SystemSettingsOpening
  let onConfirmedQuit: () -> Void

  var body: some View {
    Group {
      switch session.scanState {
      case .idle:
        WelcomeView(
          session: session,
          onChooseCustomScope: chooseCustomScope,
          onOpenSystemSettings: systemSettingsOpener.openPrivacySettings
        )
      case .scanning, .paused, .resuming, .cancelling, .cancelled,
        .completed, .failed:
        ResultsView(
          session: session,
          onChooseCustomScope: chooseCustomScope
        )
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        scanControls
      }
    }
    .confirmationDialog(
      "Quit Crazy File Manager?",
      isPresented: quitConfirmationBinding
    ) {
      Button("Keep Scanning", role: .cancel) {
        session.dismissQuitConfirmation()
      }
      Button("Quit and Cancel Scan", role: .destructive) {
        Task {
          if await session.confirmQuit() {
            onConfirmedQuit()
          }
        }
      }
    } message: {
      Text(
        "The active scan will be cancelled and its incomplete data removed before the app quits."
      )
    }
    .confirmationDialog(
      "Change file extension?",
      isPresented: renameExtensionConfirmationBinding
    ) {
      Button("Cancel", role: .cancel) {
        session.dismissRenameExtensionConfirmation()
      }
      Button("Change Extension") {
        Task {
          _ = await session.confirmRenameExtensionChange()
        }
      }
    } message: {
      Text("Changing the file extension may affect which app opens this item.")
    }
    .confirmationDialog(
      "Move to Trash?",
      isPresented: trashConfirmationBinding
    ) {
      Button("Cancel", role: .cancel) {
        session.dismissTrashConfirmation()
      }
      Button("Move to Trash", role: .destructive) {
        Task {
          _ = await session.confirmTrash()
        }
      }
    } message: {
      Text(trashConfirmationMessage)
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else {
        return
      }
      Task {
        await session.refreshCacheLifecycle()
      }
    }
  }

  @ViewBuilder
  private var scanControls: some View {
    let presentation = ScanControlPresentation.resolve(
      for: session.scanState
    )
    if let primaryAction = presentation.primaryAction {
      Button {
        perform(primaryAction)
      } label: {
        Label(
          primaryAction.title,
          systemImage: primaryAction.systemImage
        )
      }
      .disabled(!presentation.isPrimaryEnabled)
      .accessibilityIdentifier("scanPrimaryButton")
    } else if case .cancelling = session.scanState {
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Cancelling scan")
    }

    if presentation.showsCancel {
      Button("Cancel Scan", role: .destructive) {
        Task {
          _ = await session.cancelScan()
        }
      }
      .disabled(!presentation.isCancelEnabled)
      .accessibilityIdentifier("cancelScanButton")
    }
  }

  private var quitConfirmationBinding: Binding<Bool> {
    Binding(
      get: {
        session.isQuitConfirmationPresented
      },
      set: { isPresented in
        if !isPresented {
          session.dismissQuitConfirmation()
        }
      }
    )
  }

  private var renameExtensionConfirmationBinding: Binding<Bool> {
    Binding(
      get: {
        session.pendingRenameExtensionConfirmation != nil
      },
      set: { isPresented in
        if !isPresented {
          session.dismissRenameExtensionConfirmation()
        }
      }
    )
  }

  private var trashConfirmationBinding: Binding<Bool> {
    Binding(
      get: { session.pendingTrashConfirmation != nil },
      set: { isPresented in
        if !isPresented {
          session.dismissTrashConfirmation()
        }
      }
    )
  }

  private var trashConfirmationMessage: String {
    guard let confirmation = session.pendingTrashConfirmation else {
      return ""
    }
    var lines = [confirmation.name, confirmation.path]
    if let diskUsedBytes = confirmation.diskUsedBytes {
      lines.append("Disk Used: \(diskUsedBytes.formatted(.byteCount(style: .file)))")
    }
    if let descendantCount = confirmation.descendantCount {
      lines.append("Contains \(descendantCount) item\(descendantCount == 1 ? "" : "s")")
    }
    if confirmation.warnsAboutCloudSync {
      lines.append("This item may sync its removal to other devices.")
    }
    lines.append("Empty Trash to free up space.")
    return lines.joined(separator: "\n")
  }

  private func perform(_ action: ScanPrimaryAction) {
    Task {
      switch action {
      case .pause:
        _ = await session.pauseScan()
      case .resume:
        _ = await session.resumeScan()
      case .rescan:
        _ = await session.replaceScan()
      }
    }
  }

  private func chooseCustomScope() {
    guard let location = customScopeChooser.chooseFolderOrVolume() else {
      return
    }
    session.approveCustomScope(location)
  }
}

extension ScanPrimaryAction {
  fileprivate var title: String {
    switch self {
    case .pause:
      "Pause"
    case .resume:
      "Resume"
    case .rescan:
      "Rescan"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .pause:
      "pause.fill"
    case .resume:
      "play.fill"
    case .rescan:
      "arrow.clockwise"
    }
  }
}
