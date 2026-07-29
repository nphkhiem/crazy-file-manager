import SwiftUI

struct ExplorerView: View {
  let session: ExplorerSession

  var body: some View {
    switch session.scanState {
    case .idle:
      WelcomeView(session: session)
    case .scanning, .completed, .failed:
      ResultsView(session: session)
    }
  }
}
