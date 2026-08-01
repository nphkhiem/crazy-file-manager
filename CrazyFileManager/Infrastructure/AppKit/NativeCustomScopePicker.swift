import AppKit

@MainActor
struct NativeCustomScopePicker: CustomScopeChoosing {
  func chooseFolderOrVolume() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Choose a Folder or Volume"
    panel.message =
      "Crazy File Manager will retain read-only access only for the location you approve."
    panel.prompt = "Choose"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canDownloadUbiquitousContents = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    return panel.runModal() == .OK ? panel.url : nil
  }
}
