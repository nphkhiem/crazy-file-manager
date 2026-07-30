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
        try insertRoot(for: scope, into: candidate, in: database)
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
        WHERE scan_id = ? AND is_root = 0
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

  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem {
    try withDatabase { database in
      try requireScan(scan, in: database)
      return try SQLiteDatabase.withStatement(
        """
        SELECT
          item_id,
          parent_item_id,
          path,
          name,
          kind,
          aggregate_allocated_bytes,
          aggregate_logical_bytes,
          allocated_incomplete,
          logical_incomplete,
          is_root,
          EXISTS (
            SELECT 1
            FROM items AS child
            WHERE child.scan_id = items.scan_id
              AND child.parent_item_id = items.item_id
          )
        FROM items
        WHERE scan_id = ? AND is_root = 1;
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(
          scan.rawValue.uuidString,
          at: 1,
          to: statement
        )
        guard sqlite3_step(statement) == SQLITE_ROW else {
          throw SnapshotIndexError.integrityCheckFailed
        }
        return try storageTreeItem(from: statement)
      }
    }
  }

  func directChildren(
    of parentID: UUID,
    in scan: ScanID,
    offset: Int,
    limit: Int
  ) async throws -> StorageTreePage {
    guard limit > 0 else {
      return StorageTreePage(
        parentID: parentID,
        items: [],
        nextOffset: nil
      )
    }

    return try withDatabase { database in
      try requireTreeItem(parentID, in: scan, database: database)
      return try SQLiteDatabase.withStatement(
        """
        SELECT
          item_id,
          parent_item_id,
          path,
          name,
          kind,
          aggregate_allocated_bytes,
          aggregate_logical_bytes,
          allocated_incomplete,
          logical_incomplete,
          is_root,
          EXISTS (
            SELECT 1
            FROM items AS grandchild
            WHERE grandchild.scan_id = items.scan_id
              AND grandchild.parent_item_id = items.item_id
          )
        FROM items
        WHERE scan_id = ? AND parent_item_id = ?
        ORDER BY aggregate_allocated_bytes IS NULL ASC,
                 aggregate_allocated_bytes DESC,
                 name COLLATE NOCASE ASC,
                 item_id ASC
        LIMIT ? OFFSET ?;
        """,
        on: database
      ) { statement in
        let boundedLimit = min(limit, Int(Int32.max))
        let boundedOffset = min(
          max(0, offset),
          Int.max - boundedLimit
        )
        try SQLiteDatabase.bind(
          scan.rawValue.uuidString,
          at: 1,
          to: statement
        )
        try SQLiteDatabase.bind(
          parentID.uuidString,
          at: 2,
          to: statement
        )
        try SQLiteDatabase.bind(
          boundedLimit + 1,
          at: 3,
          to: statement
        )
        try SQLiteDatabase.bind(
          boundedOffset,
          at: 4,
          to: statement
        )

        var items: [StorageTreeItem] = []
        while true {
          let result = sqlite3_step(statement)
          if result == SQLITE_DONE {
            break
          }
          guard result == SQLITE_ROW else {
            throw SnapshotIndexError.statementFailed(code: result)
          }
          items.append(try storageTreeItem(from: statement))
        }

        let hasNextPage = items.count > boundedLimit
        return StorageTreePage(
          parentID: parentID,
          items: Array(items.prefix(boundedLimit)),
          nextOffset: hasNextPage
            ? boundedOffset + boundedLimit
            : nil
        )
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
        try finalizeHierarchy(for: candidate, in: database)
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
        parent_item_id TEXT,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        kind INTEGER NOT NULL,
        allocated_bytes INTEGER,
        logical_bytes INTEGER,
        is_hidden INTEGER NOT NULL,
        is_root INTEGER NOT NULL DEFAULT 0,
        tree_depth INTEGER,
        aggregate_allocated_bytes INTEGER,
        aggregate_logical_bytes INTEGER,
        allocated_incomplete INTEGER NOT NULL DEFAULT 0,
        logical_incomplete INTEGER NOT NULL DEFAULT 0,
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
    try ensureHierarchyColumns(in: database)
    try SQLiteDatabase.execute(
      """
      CREATE INDEX IF NOT EXISTS items_parent_page
      ON items (
        scan_id,
        parent_item_id,
        aggregate_allocated_bytes DESC,
        name COLLATE NOCASE,
        item_id
      );

      PRAGMA user_version = 2;
      """,
      on: database
    )
  }

  private func ensureHierarchyColumns(in database: OpaquePointer) throws {
    let columns = try itemColumnNames(in: database)
    let requiredColumns: [(name: String, definition: String)] = [
      ("parent_item_id", "TEXT"),
      ("is_root", "INTEGER NOT NULL DEFAULT 0"),
      ("tree_depth", "INTEGER"),
      ("aggregate_allocated_bytes", "INTEGER"),
      ("aggregate_logical_bytes", "INTEGER"),
      ("allocated_incomplete", "INTEGER NOT NULL DEFAULT 0"),
      ("logical_incomplete", "INTEGER NOT NULL DEFAULT 0"),
    ]

    for column in requiredColumns where !columns.contains(column.name) {
      try SQLiteDatabase.execute(
        "ALTER TABLE items ADD COLUMN \(column.name) \(column.definition);",
        on: database
      )
    }
  }

  private func itemColumnNames(in database: OpaquePointer) throws -> Set<String> {
    try SQLiteDatabase.withStatement(
      "PRAGMA table_info(items);",
      on: database
    ) { statement in
      var names: Set<String> = []
      while true {
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
          return names
        }
        guard
          result == SQLITE_ROW,
          let nameText = sqlite3_column_text(statement, 1)
        else {
          throw SnapshotIndexError.integrityCheckFailed
        }
        names.insert(String(cString: nameText))
      }
    }
  }

  private func insertRoot(
    for scope: ScanScope,
    into candidate: ScanID,
    in database: OpaquePointer
  ) throws {
    let rootID = UUID()
    let rootName =
      scope.location.lastPathComponent.isEmpty
      ? scope.location.path(percentEncoded: false)
      : scope.location.lastPathComponent
    try SQLiteDatabase.withStatement(
      """
      INSERT INTO items (
        scan_id,
        item_id,
        parent_path,
        parent_item_id,
        path,
        name,
        kind,
        allocated_bytes,
        logical_bytes,
        is_hidden,
        is_root
      )
      VALUES (?, ?, NULL, NULL, ?, ?, ?, NULL, NULL, 0, 1);
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        candidate.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(rootID.uuidString, at: 2, to: statement)
      try SQLiteDatabase.bind(
        scope.location.path(percentEncoded: false),
        at: 3,
        to: statement
      )
      try SQLiteDatabase.bind(rootName, at: 4, to: statement)
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 5,
        to: statement
      )
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func finalizeHierarchy(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try resolveParentIDs(for: scan, in: database)
    try assignTreeDepths(for: scan, in: database)
    try initializeAggregates(for: scan, in: database)
    try markIssueAncestorsIncomplete(for: scan, in: database)

    let maximumDepth = try maxTreeDepth(for: scan, in: database)
    for depth in stride(from: maximumDepth, through: 0, by: -1) {
      try aggregateFolders(
        at: depth,
        for: scan,
        in: database
      )
    }
  }

  private func resolveParentIDs(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET parent_item_id = (
        SELECT parent.item_id
        FROM items AS parent
        WHERE parent.scan_id = items.scan_id
          AND parent.path = items.parent_path
          AND parent.kind = ?
        LIMIT 1
      )
      WHERE scan_id = ? AND is_root = 0;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 2,
        to: statement
      )
      try SQLiteDatabase.requireDone(statement)
    }

    let orphanedItemCount = try countRows(
      """
      SELECT COUNT(*)
      FROM items
      WHERE scan_id = ? AND is_root = 0 AND parent_item_id IS NULL;
      """,
      for: scan,
      in: database
    )
    guard orphanedItemCount == 0 else {
      throw SnapshotIndexError.orphanedItemCount(
        actual: orphanedItemCount
      )
    }
  }

  private func assignTreeDepths(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET tree_depth = CASE WHEN is_root = 1 THEN 0 ELSE NULL END
      WHERE scan_id = ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.requireDone(statement)
    }

    while true {
      try SQLiteDatabase.withStatement(
        """
        UPDATE items
        SET tree_depth = (
          SELECT parent.tree_depth + 1
          FROM items AS parent
          WHERE parent.scan_id = items.scan_id
            AND parent.item_id = items.parent_item_id
            AND parent.tree_depth IS NOT NULL
        )
        WHERE scan_id = ?
          AND is_root = 0
          AND tree_depth IS NULL
          AND EXISTS (
            SELECT 1
            FROM items AS parent
            WHERE parent.scan_id = items.scan_id
              AND parent.item_id = items.parent_item_id
              AND parent.tree_depth IS NOT NULL
          );
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(
          scan.rawValue.uuidString,
          at: 1,
          to: statement
        )
        try SQLiteDatabase.requireDone(statement)
      }
      guard sqlite3_changes(database) > 0 else {
        break
      }
    }

    let unresolvedItemCount = try countRows(
      """
      SELECT COUNT(*)
      FROM items
      WHERE scan_id = ? AND tree_depth IS NULL;
      """,
      for: scan,
      in: database
    )
    guard unresolvedItemCount == 0 else {
      throw SnapshotIndexError.orphanedItemCount(
        actual: unresolvedItemCount
      )
    }
  }

  private func initializeAggregates(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET aggregate_allocated_bytes = CASE
            WHEN kind = ? THEN NULL
            ELSE allocated_bytes
          END,
          aggregate_logical_bytes = CASE
            WHEN kind = ? THEN NULL
            ELSE logical_bytes
          END,
          allocated_incomplete = CASE
            WHEN kind != ? AND allocated_bytes IS NULL THEN 1
            ELSE 0
          END,
          logical_incomplete = CASE
            WHEN kind != ? AND logical_bytes IS NULL THEN 1
            ELSE 0
          END
      WHERE scan_id = ?;
      """,
      on: database
    ) { statement in
      for index in 1...4 {
        try SQLiteDatabase.bind(
          StorageItemKind.folder.rawValue,
          at: Int32(index),
          to: statement
        )
      }
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 5,
        to: statement
      )
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func markIssueAncestorsIncomplete(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET allocated_incomplete = 1,
          logical_incomplete = 1
      WHERE scan_id = ?
        AND kind = ?
        AND EXISTS (
          SELECT 1
          FROM scan_issues AS issue
          WHERE issue.scan_id = items.scan_id
            AND (
              issue.path = items.path
              OR (
                items.path = '/'
                AND substr(issue.path, 1, 1) = '/'
              )
              OR substr(issue.path, 1, length(items.path) + 1)
                = items.path || '/'
            )
        );
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 2,
        to: statement
      )
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func maxTreeDepth(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws -> Int {
    try SQLiteDatabase.withStatement(
      "SELECT MAX(tree_depth) FROM items WHERE scan_id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        sqlite3_column_type(statement, 0) != SQLITE_NULL
      else {
        throw SnapshotIndexError.integrityCheckFailed
      }
      return Int(sqlite3_column_int64(statement, 0))
    }
  }

  private func aggregateFolders(
    at depth: Int,
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET aggregate_allocated_bytes = (
            SELECT SUM(child.aggregate_allocated_bytes)
            FROM items AS child
            WHERE child.scan_id = items.scan_id
              AND child.parent_item_id = items.item_id
          ),
          aggregate_logical_bytes = (
            SELECT SUM(child.aggregate_logical_bytes)
            FROM items AS child
            WHERE child.scan_id = items.scan_id
              AND child.parent_item_id = items.item_id
          ),
          allocated_incomplete = CASE
            WHEN allocated_incomplete = 1 OR EXISTS (
              SELECT 1
              FROM items AS child
              WHERE child.scan_id = items.scan_id
                AND child.parent_item_id = items.item_id
                AND child.allocated_incomplete = 1
            )
            THEN 1
            ELSE 0
          END,
          logical_incomplete = CASE
            WHEN logical_incomplete = 1 OR EXISTS (
              SELECT 1
              FROM items AS child
              WHERE child.scan_id = items.scan_id
                AND child.parent_item_id = items.item_id
                AND child.logical_incomplete = 1
            )
            THEN 1
            ELSE 0
          END
      WHERE scan_id = ? AND kind = ? AND tree_depth = ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 2,
        to: statement
      )
      try SQLiteDatabase.bind(depth, at: 3, to: statement)
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func countRows(
    _ sql: String,
    for scan: ScanID,
    in database: OpaquePointer
  ) throws -> Int {
    try SQLiteDatabase.withStatement(sql, on: database) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SnapshotIndexError.integrityCheckFailed
      }
      return Int(sqlite3_column_int64(statement, 0))
    }
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

  private func requireTreeItem(
    _ itemID: UUID,
    in scan: ScanID,
    database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      "SELECT kind FROM items WHERE scan_id = ? AND item_id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(itemID.uuidString, at: 2, to: statement)
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        StorageItemKind(
          rawValue: Int(sqlite3_column_int64(statement, 0))
        ) == .folder
      else {
        throw SnapshotIndexError.integrityCheckFailed
      }
    }
  }

  private func storageTreeItem(
    from statement: OpaquePointer
  ) throws -> StorageTreeItem {
    guard
      let idText = sqlite3_column_text(statement, 0),
      let id = UUID(uuidString: String(cString: idText)),
      let pathText = sqlite3_column_text(statement, 2),
      let nameText = sqlite3_column_text(statement, 3),
      let kind = StorageItemKind(
        rawValue: Int(sqlite3_column_int64(statement, 4))
      )
    else {
      throw SnapshotIndexError.integrityCheckFailed
    }

    let parentID: UUID?
    if sqlite3_column_type(statement, 1) == SQLITE_NULL {
      parentID = nil
    } else {
      guard
        let parentText = sqlite3_column_text(statement, 1),
        let parsedParentID = UUID(
          uuidString: String(cString: parentText)
        )
      else {
        throw SnapshotIndexError.integrityCheckFailed
      }
      parentID = parsedParentID
    }

    let diskUsedBytes =
      sqlite3_column_type(statement, 5) == SQLITE_NULL
      ? nil
      : sqlite3_column_int64(statement, 5)
    let apparentSizeBytes =
      sqlite3_column_type(statement, 6) == SQLITE_NULL
      ? nil
      : sqlite3_column_int64(statement, 6)
    let isRoot = sqlite3_column_int64(statement, 9) != 0
    guard isRoot || parentID != nil else {
      throw SnapshotIndexError.integrityCheckFailed
    }

    return StorageTreeItem(
      id: id,
      parentID: parentID,
      location: URL(
        fileURLWithPath: String(cString: pathText),
        isDirectory: kind == .folder
      ),
      name: String(cString: nameText),
      kind: kind,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: apparentSizeBytes,
      isDiskUsedIncomplete: sqlite3_column_int64(statement, 7) != 0,
      isApparentSizeIncomplete: sqlite3_column_int64(statement, 8) != 0,
      hasChildren: sqlite3_column_int64(statement, 10) != 0,
      isRoot: isRoot
    )
  }

  private func countItems(
    for candidate: ScanID,
    in database: OpaquePointer
  ) throws -> Int {
    try SQLiteDatabase.withStatement(
      "SELECT COUNT(*) FROM items WHERE scan_id = ? AND is_root = 0;",
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
