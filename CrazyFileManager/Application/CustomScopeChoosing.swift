import Foundation

@MainActor
protocol CustomScopeChoosing {
  func chooseFolderOrVolume() -> URL?
}
