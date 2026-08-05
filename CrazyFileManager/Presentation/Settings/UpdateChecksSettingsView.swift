import SwiftUI

struct UpdateChecksSettingsView: View {
  let session: UpdateCheckSession

  private var outcomePresentation: UpdateCheckOutcomePresentation? {
    UpdateCheckOutcomePresentation.resolve(session.outcome)
  }

  private var isUpdateAvailable: Bool {
    if case .available = session.outcome {
      return true
    }
    return false
  }

  var body: some View {
    Form {
      Toggle(
        "Automatically check for updates",
        isOn: Binding(
          get: { session.isAutomaticCheckEnabled },
          set: { session.setAutomaticCheckEnabled($0) }
        )
      )
      .accessibilityIdentifier("automaticUpdateCheckToggle")

      Button("Check for Updates") {
        Task {
          await session.checkForUpdatesNow()
        }
      }
      .disabled(session.isChecking)
      .accessibilityIdentifier("checkForUpdatesButton")

      if let outcomePresentation {
        VStack(alignment: .leading) {
          Text(outcomePresentation.title)
            .accessibilityIdentifier("updateCheckOutcomeTitle")
          if let detail = outcomePresentation.detail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if isUpdateAvailable {
        Button("Download Update") {
          session.beginDownloadConfirmation()
        }
        .accessibilityIdentifier("downloadUpdateButton")
      }

      if let downloadFailureMessage = session.downloadFailureMessage {
        Text(downloadFailureMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("updateDownloadFailureMessage")
      }
    }
    .padding(CFMDesign.Spacing.comfortable)
    .confirmationDialog(
      "Download this update?",
      isPresented: Binding(
        get: { session.pendingDownloadConfirmation != nil },
        set: { isPresented in
          if !isPresented {
            session.dismissDownloadConfirmation()
          }
        }
      )
    ) {
      Button("Download") {
        Task {
          await session.confirmDownload()
        }
      }
      Button("Cancel", role: .cancel) {
        session.dismissDownloadConfirmation()
      }
    } message: {
      if let metadata = session.pendingDownloadConfirmation {
        Text(
          "Crazy File Manager will download version \(metadata.version) and reveal it "
            + "in Finder. It will not be installed automatically."
        )
      }
    }
  }
}
