import Foundation
import SQLite3

actor SQLiteScanSnapshotIndex: ScanSnapshotIndexing {
  private enum ScanStatus: Int {
    case candidate
    case completed
  }

  private let databaseURL: URL

  init(databaseURL: URL) {
    self.databaseURL = databaseURL
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    let candidate = ScanID(rawValue: UUID())
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try deleteScans(with: .candidate, in: database)
        try SQLiteDatabase.withStatement(
          """
          INSERT INTO scans (id, scope_path, status, started_at)
          VALUES (?, ?, ?, ?);
          """,
          on: database
        ) { statement in
          try SQLiteDatabase.bind(
            candidate.rawValue.uuidString,
            at: 1,
            to: statement
          )
          try SQLiteDatabase.bind(
            scope.location.path(percentEncoded: false),
            at: 2,
            to: statement
          )
          try SQLiteDatabase.bind(
            ScanStatus.candidate.rawValue,
            at: 3,
            to: statement
          )
          let startedAt = Date().timeIntervalSince1970
          try SQLiteDatabase.requireSuccess(
            sqlite3_bind_double(statement, 4, startedAt)
          )
          try SQLiteDatabase.requireDone(statement)
        }
      }
    }
    return candidate
  }

  func append(_ batch: FileSystemScanBatch, to candidate: ScanID) async throws {
    try withDatabase { database in
      try requireCandidate(candidate, in: database)
      try SQLiteDatabase.transaction(on: database) {
        try append(batch.items, to: candidate, in: database)
        try append(batch.issues, to: candidate, in: database)
      }
    }
  }

  func largestItems(
    in candidate: ScanID,
    limit: Int
  ) async throws -> [StorageItemSummary] {
    try withDatabase { database in
      try requireScan(candidate, in: database)
      return try SQLiteDatabase.withStatement(
        """
        SELECT item_id, path, name, kind, allocated_bytes
        FROM items
        WHERE scan_id = ?
        ORDER BY allocated_bytes IS NULL ASC,
                 allocated_bytes DESC,
                 name COLLATE NOCASE ASC
        LIMIT ?;
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(
          candidate.rawValue.uuidString,
          at: 1,
          to: statement
        )
        try SQLiteDatabase.bind(max(0, limit), at: 2, to: statement)

        var items: [StorageItemSummary] = []
        while true {
          let result = sqlite3_step(statement)
          if result == SQLITE_DONE {
            return items
          }
          guard result == SQLITE_ROW else {
            throw SnapshotIndexError.statementFailed(code: result)
          }

          guard
            let idText = sqlite3_column_text(statement, 0),
            let id = UUID(uuidString: String(cString: idText)),
            let pathText = sqlite3_column_text(statement, 1),
            let nameText = sqlite3_column_text(statement, 2),
            let kind = StorageItemKind(
              rawValue: Int(sqlite3_column_int64(statement, 3))
            )
          else {
            throw SnapshotIndexError.integrityCheckFailed
          }

          let path = String(cString: pathText)
          let diskUsedBytes =
            sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 4)
          items.append(
            StorageItemSummary(
              id: id,
              location: URL(
                fileURLWithPath: path,
                isDirectory: kind == .folder
              ),
              name: String(cString: nameText),
              kind: kind,
              diskUsedBytes: diskUsedBytes
            )
          )
        }
      }
    }
  }

  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int
  ) async throws {
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try requireCandidate(candidate, in: database)
        let actualItemCount = try countItems(
          for: candidate,
          in: database
        )
        guard actualItemCount == expectedItemCount else {
          throw SnapshotIndexError.itemCountMismatch(
            expected: expectedItemCount,
            actual: actualItemCount
          )
        }
        let actualIssueCount = try countIssues(
          for: candidate,
          in: database
        )
        guard actualIssueCount == expectedIssueCount else {
          throw SnapshotIndexError.issueCountMismatch(
            expected: expectedIssueCount,
            actual: actualIssueCount
          )
        }
        try requireIntegrity(in: database)
        try deleteScans(with: .completed, in: database)
        try SQLiteDatabase.withStatement(
          """
          UPDATE scans
          SET status = ?, completed_at = ?
          WHERE id = ? AND status = ?;
          """,
          on: database
        ) { statement in
          try SQLiteDatabase.bind(
            ScanStatus.completed.rawValue,
            at: 1,
            to: statement
          )
          try SQLiteDatabase.requireSuccess(
            sqlite3_bind_double(
              statement,
              2,
              Date().timeIntervalSince1970
            )
          )
          try SQLiteDatabase.bind(
            candidate.rawValue.uuidString,
            at: 3,
            to: statement
          )
          try SQLiteDatabase.bind(
            ScanStatus.candidate.rawValue,
            at: 4,
            to: statement
          )
          try SQLiteDatabase.requireDone(statement)
          guard sqlite3_changes(database) == 1 else {
            throw SnapshotIndexError.candidateNotFound
          }
        }
      }
    }
  }

  func discardCandidate(_ candidate: ScanID) async throws {
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try SQLiteDatabase.withStatement(
          "DELETE FROM scans WHERE id = ? AND status = ?;",
          on: database
        ) { statement in
          try SQLiteDatabase.bind(
            candidate.rawValue.uuidString,
            at: 1,
            to: statement
          )
          try SQLiteDatabase.bind(
            ScanStatus.candidate.rawValue,
            at: 2,
            to: statement
          )
          try SQLiteDatabase.requireDone(statement)
        }
      }
    }
  }

  private func withDatabase<Result>(
    operation: (OpaquePointer) throws -> Result
  ) throws -> Result {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try createSchema(in: database)
      return try operation(database)
    }
  }

  private func createSchema(in database: OpaquePointer) throws {
    try SQLiteDatabase.execute(
      """
      CREATE TABLE IF NOT EXISTS scans (
        id TEXT PRIMARY KEY NOT NULL,
        scope_path TEXT NOT NULL,
        status INTEGER NOT NULL,
        started_at REAL NOT NULL,
        completed_at REAL
      );

      CREATE TABLE IF NOT EXISTS items (
        scan_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        parent_path TEXT,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        kind INTEGER NOT NULL,
        allocated_bytes INTEGER,
        logical_bytes INTEGER,
        is_hidden INTEGER NOT NULL,
        PRIMARY KEY (scan_id, item_id),
        UNIQUE (scan_id, path),
        FOREIGN KEY (scan_id) REFERENCES scans(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS items_largest
      ON items (scan_id, allocated_bytes DESC, name COLLATE NOCASE);

      CREATE TABLE IF NOT EXISTS scan_issues (
        scan_id TEXT NOT NULL,
        path TEXT NOT NULL,
        kind INTEGER NOT NULL,
        message TEXT NOT NULL,
        FOREIGN KEY (scan_id) REFERENCES scans(id) ON DELETE CASCADE
      );
      """,
      on: database
    )
  }

  private func deleteScans(
    with status: ScanStatus,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      "DELETE FROM scans WHERE status = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(status.rawValue, at: 1, to: statement)
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func requireCandidate(
    _ candidate: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      "SELECT status FROM scans WHERE id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        candidate.rawValue.uuidString,
        at: 1,
        to: statement
      )
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        Int(sqlite3_column_int64(statement, 0)) == ScanStatus.candidate.rawValue
      else {
        throw SnapshotIndexError.candidateNotFound
      }
    }
  }

  private func requireScan(
    _ scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      "SELECT 1 FROM scans WHERE id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SnapshotIndexError.candidateNotFound
      }
    }
  }

  private func countItems(
    for candidate: ScanID,
    in database: OpaquePointer
  ) throws -> Int {
    try SQLiteDatabase.withStatement(
      "SELECT COUNT(*) FROM items WHERE scan_id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        candidate.rawValue.uuidString,
        at: 1,
        to: statement
      )
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SnapshotIndexError.integrityCheckFailed
      }
      return Int(sqlite3_column_int64(statement, 0))
    }
  }

  private func countIssues(
    for candidate: ScanID,
    in database: OpaquePointer
  ) throws -> Int {
    try SQLiteDatabase.withStatement(
      "SELECT COUNT(*) FROM scan_issues WHERE scan_id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        candidate.rawValue.uuidString,
        at: 1,
        to: statement
      )
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SnapshotIndexError.integrityCheckFailed
      }
      return Int(sqlite3_column_int64(statement, 0))
    }
  }

  private func requireIntegrity(in database: OpaquePointer) throws {
    try SQLiteDatabase.withStatement(
      "PRAGMA quick_check;",
      on: database
    ) { statement in
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        let resultText = sqlite3_column_text(statement, 0),
        String(cString: resultText) == "ok"
      else {
        throw SnapshotIndexError.integrityCheckFailed
      }
    }
  }

  private func append(
    _ items: [ScannedItem],
    to candidate: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      INSERT INTO items (
        scan_id,
        item_id,
        parent_path,
        path,
        name,
        kind,
        allocated_bytes,
        logical_bytes,
        is_hidden
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
      """,
      on: database
    ) { statement in
      for item in items {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try SQLiteDatabase.bind(
          candidate.rawValue.uuidString,
          at: 1,
          to: statement
        )
        try SQLiteDatabase.bind(item.id.uuidString, at: 2, to: statement)
        try SQLiteDatabase.bind(item.parentPath, at: 3, to: statement)
        try SQLiteDatabase.bind(
          item.location.path(percentEncoded: false),
          at: 4,
          to: statement
        )
        try SQLiteDatabase.bind(item.name, at: 5, to: statement)
        try SQLiteDatabase.bind(item.kind.rawValue, at: 6, to: statement)
        try SQLiteDatabase.bind(item.diskUsedBytes, at: 7, to: statement)
        try SQLiteDatabase.bind(
          item.apparentSizeBytes,
          at: 8,
          to: statement
        )
        try SQLiteDatabase.bind(item.isHidden ? 1 : 0, at: 9, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
    }
  }

  private func append(
    _ issues: [ScanIssue],
    to candidate: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      INSERT INTO scan_issues (scan_id, path, kind, message)
      VALUES (?, ?, ?, ?);
      """,
      on: database
    ) { statement in
      for issue in issues {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try SQLiteDatabase.bind(
          candidate.rawValue.uuidString,
          at: 1,
          to: statement
        )
        try SQLiteDatabase.bind(
          issue.location.path(percentEncoded: false),
          at: 2,
          to: statement
        )
        try SQLiteDatabase.bind(issue.kind.rawValue, at: 3, to: statement)
        try SQLiteDatabase.bind(issue.message, at: 4, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
    }
  }
}
