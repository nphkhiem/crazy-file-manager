import SwiftUI

struct SettingsView: View {
  let session: ExplorerSession
  let updateCheckSession: UpdateCheckSession

  var body: some View {
    TabView {
      ScanDataSettingsView(session: session)
        .tabItem {
          Label("Scan Data", systemImage: "externaldrive")
        }

      UpdateChecksSettingsView(session: updateCheckSession)
        .tabItem {
          Label("Update Checks", systemImage: "arrow.triangle.2.circlepath")
        }

      PrivacySettingsView()
        .tabItem {
          Label("Privacy", systemImage: "hand.raised")
        }

      AboutSettingsView()
        .tabItem {
          Label("About", systemImage: "info.circle")
        }
    }
    .frame(width: 420, height: 360)
  }
}
