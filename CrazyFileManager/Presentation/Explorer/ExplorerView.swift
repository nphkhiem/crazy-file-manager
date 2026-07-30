import SwiftUI

struct ExplorerView: View {
  let session: ExplorerSession

  var body: some View {
    switch session.scanState {
    case .idle:
      WelcomeView(session: session)
    case .scanning, .paused, .resuming, .cancelling, .cancelled, .completed,
      .failed:
      ResultsView(session: session)
    }
  }
}
