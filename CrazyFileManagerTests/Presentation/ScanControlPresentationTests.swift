import AppKit
import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Scan Control Presentation")
struct ScanControlPresentationTests {
  @Test
  func givenEachScanState_whenControlsResolve_thenStableActionsRemainCorrect() {
    let progress = ScanProgress.initial
    let completion = ScanCompletion(
      accessibleItemCount: 1,
      issueCount: 0
    )
    let failure = ScanFailure(message: "The scan stopped.")
    let expectations: [(ScanState, ScanControlPresentation)] = [
      (
        .idle,
        .init(
          primaryAction: nil,
          isPrimaryEnabled: false,
          showsCancel: false,
          isCancelEnabled: false
        )
      ),
      (
        .scanning(progress),
        .init(
          primaryAction: .pause,
          isPrimaryEnabled: true,
          showsCancel: true,
          isCancelEnabled: true
        )
      ),
      (
        .paused(progress),
        .init(
          primaryAction: .resume,
          isPrimaryEnabled: true,
          showsCancel: true,
          isCancelEnabled: true
        )
      ),
      (
        .resuming(progress),
        .init(
          primaryAction: .resume,
          isPrimaryEnabled: false,
          showsCancel: true,
          isCancelEnabled: true
        )
      ),
      (
        .cancelling(progress),
        .init(
          primaryAction: nil,
          isPrimaryEnabled: false,
          showsCancel: true,
          isCancelEnabled: false
        )
      ),
      (
        .cancelled,
        .init(
          primaryAction: .rescan,
          isPrimaryEnabled: true,
          showsCancel: false,
          isCancelEnabled: false
        )
      ),
      (
        .completed(completion),
        .init(
          primaryAction: .rescan,
          isPrimaryEnabled: true,
          showsCancel: false,
          isCancelEnabled: false
        )
      ),
      (
        .failed(failure),
        .init(
          primaryAction: .rescan,
          isPrimaryEnabled: true,
          showsCancel: false,
          isCancelEnabled: false
        )
      ),
    ]

    for (state, expected) in expectations {
      #expect(ScanControlPresentation.resolve(for: state) == expected)
    }
  }

  @Test
  func givenKnownAndUnknownProgress_whenProgressResolves_thenDeterminateStateIsHonest() {
    let known = ScanProgress(
      discoveredItemCount: 25,
      issueCount: 0,
      currentArea: nil,
      fractionCompleted: 0.25
    )
    let unknown = ScanProgress(
      discoveredItemCount: 25,
      issueCount: 0,
      currentArea: nil
    )

    #expect(
      ScanProgressPresentation.resolve(for: .scanning(known))
        == .determinate(0.25)
    )
    #expect(
      ScanProgressPresentation.resolve(for: .scanning(unknown))
        == .indeterminate
    )
    #expect(
      ScanProgressPresentation.resolve(
        for: .completed(
          ScanCompletion(
            accessibleItemCount: 25,
            issueCount: 0
          )
        )) == .hidden
    )
  }

  @Test
  func givenActiveScan_whenTerminationIsRequested_thenDelegateRequestsConfirmation()
    async
  {
    let fixture = TerminationFixture()
    #expect(fixture.session.startScan())
    await eventually {
      await fixture.scanner.requestedScopes.count == 1
    }
    var terminationRequestCount = 0
    let controller = ApplicationTerminationController {
      terminationRequestCount += 1
    }
    controller.session = fixture.session

    let reply = controller.applicationShouldTerminate(.shared)

    #expect(reply == .terminateCancel)
    #expect(fixture.session.isQuitConfirmationPresented)
    #expect(terminationRequestCount == 0)
    fixture.session.dismissQuitConfirmation()
    _ = await fixture.session.cancelScan()
  }

  @Test
  func givenConfirmedQuit_whenTerminationIsRequestedAgain_thenDelegateAllowsTerminationOnce()
    async
  {
    let fixture = TerminationFixture()
    #expect(fixture.session.startScan())
    await eventually {
      await fixture.scanner.requestedScopes.count == 1
    }
    var terminationRequestCount = 0
    let controller = ApplicationTerminationController {
      terminationRequestCount += 1
    }
    controller.session = fixture.session
    #expect(
      fixture.session.requestQuit()
        == .confirmScanCancellation
    )
    #expect(await fixture.session.confirmQuit())
    controller.completeConfirmedTermination()

    #expect(terminationRequestCount == 1)
    #expect(
      controller.applicationShouldTerminate(.shared)
        == .terminateNow
    )
    #expect(await fixture.session.replaceScan())
    await eventually {
      await fixture.scanner.requestedScopes.count == 2
    }
    #expect(
      controller.applicationShouldTerminate(.shared)
        == .terminateCancel
    )
    #expect(fixture.session.isQuitConfirmationPresented)
    fixture.session.dismissQuitConfirmation()
    _ = await fixture.session.cancelScan()
  }
}

@MainActor
private struct TerminationFixture {
  let scanner = ControlledFileSystemScanner()
  let index = InMemoryScanSnapshotIndex()
  let session: ExplorerSession

  init() {
    session = ExplorerSession(
      homeDirectoryURL: URL(
        fileURLWithPath: "/Users/tester",
        isDirectory: true
      ),
      scanner: scanner,
      snapshotIndex: index
    )
  }
}
