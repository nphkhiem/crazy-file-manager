import Foundation

@testable import CrazyFileManager

final class ControlledScanScopeAuthorizer:
  ScanScopeAuthorizing,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let descriptions: [ScanScopeDescription]
  private var preparedScopes: [PreparedSelection] = []
  private var finishedLeases = 0

  private struct PreparedSelection {
    let selection: ScanScopeSelection
    let scope: ScanScope
  }

  init(descriptions: [ScanScopeDescription]) {
    self.descriptions = descriptions
  }

  var finishedLeaseCount: Int {
    lock.withLock { finishedLeases }
  }

  func describe(_ selection: ScanScopeSelection) -> ScanScopeDescription {
    lock.withLock {
      descriptions.first { $0.selection == selection }
        ?? ScanScopeDescription(
          selection: selection,
          availability: .unsupported(
            location: URL(filePath: "/unconfigured")
          )
        )
    }
  }

  func prepare(_ selection: ScanScopeSelection) -> ScanScopePreparation {
    if let scope = lock.withLock({
      preparedScopes.first { $0.selection == selection }?.scope
    }) {
      return .ready(
        PreparedScanScope(
          scope: scope,
          accessLease: makeAccessLease()
        )
      )
    }
    let description = describe(selection)
    guard case .available(let scope) = description.availability else {
      return .unavailable(description)
    }
    return .ready(
      PreparedScanScope(
        scope: scope,
        accessLease: makeAccessLease()
      )
    )
  }

  func setPreparedScope(
    _ scope: ScanScope,
    for selection: ScanScopeSelection
  ) {
    lock.withLock {
      preparedScopes.removeAll { $0.selection == selection }
      preparedScopes.append(
        PreparedSelection(selection: selection, scope: scope)
      )
    }
  }

  private func makeAccessLease() -> any ScanScopeAccessLeasing {
    ControlledScanScopeAccessLease { [weak self] in
      guard let self else {
        return
      }
      self.lock.withLock {
        self.finishedLeases += 1
      }
    }
  }
}

private final class ControlledScanScopeAccessLease:
  ScanScopeAccessLeasing,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let onFinish: @Sendable () -> Void
  private var isFinished = false

  init(onFinish: @escaping @Sendable () -> Void) {
    self.onFinish = onFinish
  }

  func finish() {
    let shouldFinish = lock.withLock {
      guard !isFinished else {
        return false
      }
      isFinished = true
      return true
    }
    if shouldFinish {
      onFinish()
    }
  }
}
