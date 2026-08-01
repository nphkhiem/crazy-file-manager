import SwiftUI

struct ExplorerView: View {
  let session: ExplorerSession
  let onConfirmedQuit: () -> Void

  var body: some View {
    Group {
      switch session.scanState {
      case .idle:
        WelcomeView(session: session)
      case .scanning, .paused, .resuming, .cancelling, .cancelled,
        .completed, .failed:
        ResultsView(session: session)
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
