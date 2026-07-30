import Foundation

@testable import CrazyFileManager

actor ControlledFileSystemScanner: FileSystemScanning {
  private(set) var requestedScopes: [ScanScope] = []
  private(set) var nextBatchRequestCount = 0

  private var activeStreamID: UUID?
  private var queuedBatches: [FileSystemScanBatch] = []
  private var pendingRequest: CheckedContinuation<FileSystemScanBatch?, any Error>?
  private var terminalError: (any Error)?
  private var isFinished = false

  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
    let streamID = UUID()
    requestedScopes.append(scope)
    activeStreamID = streamID
    queuedBatches = []
    terminalError = nil
    isFinished = false

    return AsyncThrowingStream {
      try await self.nextBatch(for: streamID)
    }
  }

  func yield(_ batch: FileSystemScanBatch) {
    guard !isFinished, terminalError == nil else {
      return
    }
    if let pendingRequest {
      self.pendingRequest = nil
      pendingRequest.resume(returning: batch)
    } else {
      queuedBatches.append(batch)
    }
  }

  func finish() {
    isFinished = true
    if queuedBatches.isEmpty, let pendingRequest {
      self.pendingRequest = nil
      pendingRequest.resume(returning: nil)
    }
  }

  func fail(_ error: any Error) {
    terminalError = error
    if queuedBatches.isEmpty, let pendingRequest {
      self.pendingRequest = nil
      pendingRequest.resume(throwing: error)
    }
  }

  private func nextBatch(for streamID: UUID) async throws
    -> FileSystemScanBatch?
  {
    try Task.checkCancellation()
    guard activeStreamID == streamID else {
      throw CancellationError()
    }
    nextBatchRequestCount += 1

    if !queuedBatches.isEmpty {
      return queuedBatches.removeFirst()
    }
    if let terminalError {
      throw terminalError
    }
    if isFinished {
      return nil
    }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pendingRequest = continuation
      }
    } onCancel: {
      Task {
        await self.cancelStream(streamID)
      }
    }
  }

  private func cancelStream(_ streamID: UUID) {
    guard activeStreamID == streamID else {
      return
    }
    isFinished = true
    pendingRequest?.resume(throwing: CancellationError())
    pendingRequest = nil
  }
}

enum ControlledScanError: Error {
  case failed
}
