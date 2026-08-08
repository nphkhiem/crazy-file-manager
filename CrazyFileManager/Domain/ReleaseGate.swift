import Foundation

enum ReleaseGate {
  static var mutationsPendingIndependentReview: Bool {
    #if PUBLIC_RELEASE_MUTATIONS_PENDING_REVIEW
      return true
    #else
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiSimulatePublicReleaseGate") {
          return true
        }
      #endif
      return false
    #endif
  }
}
