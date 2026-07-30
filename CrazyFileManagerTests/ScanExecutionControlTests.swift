import Testing

@testable import CrazyFileManager

@Suite("Scan Execution Control")
struct ScanExecutionControlTests {
  @Test
  func givenPausedControl_whenWaitBegins_thenResumeReleasesWaiter()
    async throws
  {
    let control = ScanExecutionControl()
    let completion = CompletionProbe()
    #expect(await control.pause())
    let waiter = Task {
      try await control.waitUntilRunning()
      await completion.markCompleted()
    }
    await Task.yield()

    #expect(!(await completion.isCompleted))
    #expect(await control.resume())
    try await waiter.value
    #expect(await completion.isCompleted)
  }

  @Test
  func givenPausedControl_whenWaitBegins_thenCancelThrowsCancellation()
    async
  {
    let control = ScanExecutionControl()
    #expect(await control.pause())
    let waiter = Task {
      try await control.waitUntilRunning()
    }
    await Task.yield()

    await control.cancel()

    await #expect(throws: CancellationError.self) {
      try await waiter.value
    }
  }
}

private actor CompletionProbe {
  private(set) var isCompleted = false

  func markCompleted() {
    isCompleted = true
  }
}
