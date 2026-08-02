import Foundation
import SQLite3

actor SQLiteScanSnapshotIndex: ScanSnapshotIndexing {
  private enum ScanStatus: Int {
    case candidate
    case completed
  }

  private struct CompletedSnapshotMetadata {
    let scanID: ScanID?
    let scope: ScanScope?
    let completion: ScanCompletion
    let completedAt: Date?
    let expiresAt: Date?
    let snapshotSchemaVersion: Int?

    var isValid: Bool {
      guard
        scanID != nil,
        scope != nil,
        let completedAt,
        let expiresAt,
        snapshotSchemaVersion == 1
      else {
        return false
      }
      let completedInterval = completedAt.timeIntervalSince1970
      let expiryInterval = expiresAt.timeIntervalSince1970
      let expectedExpiryInterval = completedInterval + 86_400
      return completedInterval.isFinite
        && expiryInterval.isFinite
        && expectedExpiryInterval.isFinite
        && expiryInterval == expectedExpiryInterval
    }
  }

  private let databaseURL: URL
  private let dateProvider: any DateProviding

  init(
    databaseURL: URL,
    dateProvider: any DateProviding = SystemDateProvider()
  ) {
    self.databaseURL = databaseURL
    self.dateProvider = dateProvider
  }

  func removeCrashLeftoverCandidates() async throws {
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try deleteScans(with: .candidate, in: database)
      }
    }
  }

  func prepareCacheForLaunch(
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> ScanCachePreparation {
    do {
      return try prepareCompletedCache(
        largestItemLimit: largestItemLimit,
        treePageLimit: treePageLimit,
        removesCandidates: true
      )
    } catch {
      guard shouldReconstruct(for: error) else {
        throw error
      }
      try reconstructDatabase()
      return .reconstructed
    }
  }

  func refreshCompletedCache(
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> ScanCachePreparation {
    do {
      return try prepareCompletedCache(
        largestItemLimit: largestItemLimit,
        treePageLimit: treePageLimit,
        removesCandidates: false
      )
    } catch {
      guard shouldReconstruct(for: error) else {
        throw error
      }
      try reconstructDatabase()
      return .reconstructed
    }
  }

  func clearCompletedSnapshot() async throws {
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try deleteScans(with: .completed, in: database)
      }
    }
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    let candidate = ScanID(rawValue: UUID())
    try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try deleteScans(with: .candidate, in: database)
        try SQLiteDatabase.withStatement(
          """
          INSERT INTO scans (
            id,
            scope_path,
            scope_kind,
            scope_volume_identity,
            scope_is_internal,
            scope_is_read_only,
            scope_is_removable,
            status,
            started_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            scope.kind.persistedValue,
            at: 3,
            to: statement
          )
          try SQLiteDatabase.bind(
            scope.volumeIdentity.rawValue,
            at: 4,
            to: statement
          )
          try SQLiteDatabase.bind(
            scope.volumeCharacteristics.isInternal.map { $0 ? Int64(1) : Int64(0) },
            at: 5,
            to: statement
          )
          try SQLiteDatabase.bind(
            scope.volumeCharacteristics.isReadOnly.map { $0 ? Int64(1) : Int64(0) },
            at: 6,
            to: statement
          )
          try SQLiteDatabase.bind(
            scope.volumeCharacteristics.isRemovable.map { $0 ? Int64(1) : Int64(0) },
            at: 7,
            to: statement
          )
          try SQLiteDatabase.bind(
            ScanStatus.candidate.rawValue,
            at: 8,
            to: statement
          )
          let startedAt = dateProvider.now().timeIntervalSince1970
          try SQLiteDatabase.requireSuccess(
            sqlite3_bind_double(statement, 9, startedAt)
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
      return try largestItems(
        in: candidate,
        limit: limit,
        database: database
      )
    }
  }

  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem {
    try withDatabase { database in
      try requireScan(scan, in: database)
      return try treeRoot(in: scan, database: database)
    }
  }

  func itemDetail(for itemID: UUID, in scan: ScanID) async throws -> StorageItemDetail? {
    try withDatabase { database in
      try requireScan(scan, in: database)
      return try itemDetail(for: itemID, in: scan, database: database)
    }
  }

  func updateItemName(
    _ itemID: UUID,
    in scan: ScanID,
    newName: String,
    newPath: String
  ) async throws {
    try withDatabase { database in
      try requireScan(scan, in: database)
      try SQLiteDatabase.transaction(on: database) {
        let oldPath = try itemPath(of: itemID, in: scan, database: database)
        try SQLiteDatabase.withStatement(
          "UPDATE items SET name = ?, path = ? WHERE scan_id = ? AND item_id = ?;",
          on: database
        ) { statement in
          try SQLiteDatabase.bind(newName, at: 1, to: statement)
          try SQLiteDatabase.bind(newPath, at: 2, to: statement)
          try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 3, to: statement)
          try SQLiteDatabase.bind(itemID.uuidString, at: 4, to: statement)
          try SQLiteDatabase.requireDone(statement)
        }
        try relocateDescendants(
          of: itemID,
          in: scan,
          oldPath: oldPath,
          newPath: newPath,
          database: database
        )
      }
    }
  }

  private func itemPath(
    of itemID: UUID,
    in scan: ScanID,
    database: OpaquePointer
  ) throws -> String {
    try SQLiteDatabase.withStatement(
      "SELECT path FROM items WHERE scan_id = ? AND item_id = ?;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      try SQLiteDatabase.bind(itemID.uuidString, at: 2, to: statement)
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        let pathText = sqlite3_column_text(statement, 0)
      else {
        throw SnapshotIndexError.candidateNotFound
      }
      return String(cString: pathText)
    }
  }

  private func relocateDescendants(
    of itemID: UUID,
    in scan: ScanID,
    oldPath: String,
    newPath: String,
    database: OpaquePointer
  ) throws {
    let descendants = try SQLiteDatabase.withStatement(
      """
      WITH RECURSIVE descendants(item_id, path, parent_path) AS (
        SELECT item_id, path, parent_path FROM items
        WHERE scan_id = ? AND parent_item_id = ?
        UNION ALL
        SELECT items.item_id, items.path, items.parent_path
        FROM items
        JOIN descendants ON items.parent_item_id = descendants.item_id
        WHERE items.scan_id = ?
      )
      SELECT item_id, path, parent_path FROM descendants;
      """,
      on: database
    ) { statement -> [(id: String, path: String, parentPath: String?)] in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      try SQLiteDatabase.bind(itemID.uuidString, at: 2, to: statement)
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 3, to: statement)

      var rows: [(id: String, path: String, parentPath: String?)] = []
      while true {
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
          return rows
        }
        guard result == SQLITE_ROW, let pathText = sqlite3_column_text(statement, 1)
        else {
          throw SnapshotIndexError.statementFailed(code: result)
        }
        guard let idText = sqlite3_column_text(statement, 0) else {
          throw SnapshotIndexError.integrityCheckFailed
        }
        let parentPath = sqlite3_column_text(statement, 2).map { String(cString: $0) }
        rows.append(
          (
            id: String(cString: idText),
            path: String(cString: pathText),
            parentPath: parentPath
          )
        )
      }
    }

    for descendant in descendants {
      let relocatedPath = PathRelocation.rewritten(
        descendant.path,
        oldPrefix: oldPath,
        newPrefix: newPath
      )
      let relocatedParentPath = descendant.parentPath.map {
        PathRelocation.rewritten($0, oldPrefix: oldPath, newPrefix: newPath)
      }
      try SQLiteDatabase.withStatement(
        "UPDATE items SET path = ?, parent_path = ? WHERE scan_id = ? AND item_id = ?;",
        on: database
      ) { statement in
        try SQLiteDatabase.bind(relocatedPath, at: 1, to: statement)
        try SQLiteDatabase.bind(relocatedParentPath, at: 2, to: statement)
        try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 3, to: statement)
        try SQLiteDatabase.bind(descendant.id, at: 4, to: statement)
        try SQLiteDatabase.requireDone(statement)
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
      try directChildren(
        of: parentID,
        in: scan,
        offset: offset,
        limit: limit,
        database: database
      )
    }
  }

  private func prepareCompletedCache(
    largestItemLimit: Int,
    treePageLimit: Int,
    removesCandidates: Bool
  ) throws -> ScanCachePreparation {
    try withDatabase { database in
      if removesCandidates {
        try requireIntegrity(in: database)
      }
      return try SQLiteDatabase.transaction(on: database) {
        if removesCandidates {
          try deleteScans(with: .candidate, in: database)
        }
        guard let metadata = try completedSnapshotMetadata(in: database) else {
          return .empty
        }
        guard metadata.isValid else {
          throw SnapshotIndexError.invalidSnapshotMetadata
        }

        guard
          let scanID = metadata.scanID,
          let scope = metadata.scope,
          let completedAt = metadata.completedAt,
          let expiresAt = metadata.expiresAt
        else {
          throw SnapshotIndexError.integrityCheckFailed
        }

        let now = dateProvider.now()
        let isStale = now < completedAt || now >= expiresAt
        guard !isStale else {
          do {
            try deleteScans(with: .completed, in: database)
          } catch {
            return .cleanupFailed(
              previousScope: scope,
              completedAt: completedAt
            )
          }
          return .expired(
            previousScope: scope,
            completedAt: completedAt
          )
        }

        let largestItems = try largestItems(
          in: scanID,
          limit: largestItemLimit,
          database: database
        )
        let root = try treeRoot(in: scanID, database: database)
        let rootPage = try directChildren(
          of: root.id,
          in: scanID,
          offset: 0,
          limit: treePageLimit,
          database: database
        )
        return .available(
          CachedScanSnapshot(
            scanID: scanID,
            scope: scope,
            completion: metadata.completion,
            completedAt: completedAt,
            expiresAt: expiresAt,
            largestItems: largestItems,
            treeRoot: root,
            rootPage: rootPage
          )
        )
      }
    }
  }

  private func completedSnapshotMetadata(
    in database: OpaquePointer
  ) throws -> CompletedSnapshotMetadata? {
    try SQLiteDatabase.withStatement(
      """
      SELECT
        id,
        scope_path,
        scope_kind,
        scope_volume_identity,
        scope_is_internal,
        scope_is_read_only,
        scope_is_removable,
        completed_at,
        expires_at,
        snapshot_schema_version,
        (
          SELECT COUNT(*)
          FROM items
          WHERE items.scan_id = scans.id AND items.is_root = 0
        ),
        (SELECT COUNT(*) FROM scan_issues WHERE scan_issues.scan_id = scans.id)
      FROM scans
      WHERE status = ?
      LIMIT 1;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        ScanStatus.completed.rawValue,
        at: 1,
        to: statement
      )
      let result = sqlite3_step(statement)
      guard result != SQLITE_DONE else {
        return nil
      }
      guard result == SQLITE_ROW else {
        throw SnapshotIndexError.statementFailed(code: result)
      }

      let scanID = sqlite3_column_text(statement, 0).flatMap {
        UUID(uuidString: String(cString: $0))
      }.map(ScanID.init(rawValue:))
      let scope = scanScope(from: statement)
      let completedAt = dateValue(at: 7, in: statement)
      let expiresAt = dateValue(at: 8, in: statement)
      let snapshotSchemaVersion = integerValue(at: 9, in: statement)
      return CompletedSnapshotMetadata(
        scanID: scanID,
        scope: scope,
        completion: ScanCompletion(
          accessibleItemCount: Int(sqlite3_column_int64(statement, 10)),
          issueCount: Int(sqlite3_column_int64(statement, 11))
        ),
        completedAt: completedAt,
        expiresAt: expiresAt,
        snapshotSchemaVersion: snapshotSchemaVersion
      )
    }
  }

  private func scanScope(from statement: OpaquePointer) -> ScanScope? {
    guard
      let scopePath = sqlite3_column_text(statement, 1),
      let kind = ScanScope.Kind(
        persistedValue: Int(sqlite3_column_int64(statement, 2))
      ),
      let volumeIdentity = sqlite3_column_text(statement, 3)
    else {
      return nil
    }
    let scopePathValue = String(cString: scopePath)
    let volumeIdentityValue = String(cString: volumeIdentity)
    guard !scopePathValue.isEmpty,
      !volumeIdentityValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return ScanScope(
      kind: kind,
      location: URL(fileURLWithPath: scopePathValue),
      volumeIdentity: ScanVolumeIdentity(rawValue: volumeIdentityValue),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: boolValue(at: 4, in: statement),
        isReadOnly: boolValue(at: 5, in: statement),
        isRemovable: boolValue(at: 6, in: statement)
      )
    )
  }

  private func dateValue(
    at index: Int32,
    in statement: OpaquePointer
  ) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    let interval = sqlite3_column_double(statement, index)
    guard interval.isFinite else {
      return nil
    }
    return Date(timeIntervalSince1970: interval)
  }

  private func integerValue(
    at index: Int32,
    in statement: OpaquePointer
  ) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    return Int(sqlite3_column_int64(statement, index))
  }

  private func largestItems(
    in scan: ScanID,
    limit: Int,
    database: OpaquePointer
  ) throws -> [StorageItemSummary] {
    try SQLiteDatabase.withStatement(
      """
      WITH package_descendants AS (
        SELECT
          package.item_id AS package_id,
          descendant.item_id,
          descendant.kind,
          descendant.allocated_bytes,
          descendant.file_system_identity,
          descendant.hard_link_count,
          descendant.is_cloud_only
        FROM items AS package
        JOIN items AS descendant
          ON descendant.scan_id = package.scan_id
          AND substr(
            descendant.path,
            1,
            length(rtrim(package.path, '/')) + 1
          ) = rtrim(package.path, '/') || '/'
        WHERE package.scan_id = ? AND package.kind = ?
      ),
      package_identity_totals AS (
        SELECT
          package_id,
          coalesce(file_system_identity, item_id) AS evidence_identity,
          MAX(allocated_bytes) AS allocated_bytes
        FROM package_descendants
        WHERE kind NOT IN (?, ?)
        GROUP BY package_id, evidence_identity
      ),
      package_evidence AS (
        SELECT
          descendant.package_id,
          (
            SELECT SUM(identity_total.allocated_bytes)
            FROM package_identity_totals AS identity_total
            WHERE identity_total.package_id = descendant.package_id
          ) AS allocated_bytes,
          MAX(
            CASE
              WHEN descendant.kind NOT IN (?, ?)
                AND descendant.file_system_identity IS NOT NULL
                AND descendant.hard_link_count > 1
              THEN 1
              ELSE 0
            END
          ) AS is_shared,
          MAX(descendant.is_cloud_only) AS is_cloud_only
        FROM package_descendants AS descendant
        GROUP BY descendant.package_id
      )
      SELECT
        item.item_id, item.path, item.name, item.kind,
        CASE
          WHEN item.kind = ? THEN CASE
            WHEN package_evidence.package_id IS NULL
              THEN item.allocated_bytes
            ELSE package_evidence.allocated_bytes
          END
          ELSE item.allocated_bytes
        END AS reported_allocated_bytes,
        CASE
          WHEN item.is_shared = 1
            OR coalesce(package_evidence.is_shared, 0) = 1
            OR (
              item.kind NOT IN (?, ?)
              AND item.file_system_identity IS NOT NULL
              AND item.hard_link_count > 1
            )
          THEN 1
          ELSE 0
        END,
        item.is_hidden,
        CASE
          WHEN item.is_cloud_only = 1
            OR coalesce(package_evidence.is_cloud_only, 0) = 1
          THEN 1
          ELSE 0
        END
      FROM items AS item
      LEFT JOIN package_evidence
        ON package_evidence.package_id = item.item_id
      WHERE item.scan_id = ?
        AND item.is_root = 0
        AND item.is_package_descendant = 0
        AND NOT EXISTS (
          SELECT 1
          FROM items AS package
          WHERE package.scan_id = item.scan_id
            AND package.kind = ?
            AND package.item_id != item.item_id
            AND substr(
              item.path,
              1,
              length(rtrim(package.path, '/')) + 1
            ) = rtrim(package.path, '/') || '/'
        )
      ORDER BY reported_allocated_bytes IS NULL ASC,
               reported_allocated_bytes DESC,
               item.name COLLATE NOCASE ASC
      LIMIT ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 2,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 3,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 4,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 5,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 6,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 7,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 8,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 9,
        to: statement
      )
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 10,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 11,
        to: statement
      )
      try SQLiteDatabase.bind(max(0, limit), at: 12, to: statement)

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
            diskUsedBytes: diskUsedBytes,
            isShared: sqlite3_column_int64(statement, 5) != 0,
            isHidden: sqlite3_column_int64(statement, 6) != 0,
            isCloudOnly: sqlite3_column_int64(statement, 7) != 0
          )
        )
      }
    }
  }

  private func treeRoot(
    in scan: ScanID,
    database: OpaquePointer
  ) throws -> StorageTreeItem {
    try SQLiteDatabase.withStatement(
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
        ),
        is_shared,
        is_hidden,
        is_cloud_only
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

  private func itemDetail(
    for itemID: UUID,
    in scan: ScanID,
    database: OpaquePointer
  ) throws -> StorageItemDetail? {
    try SQLiteDatabase.withStatement(
      """
      SELECT
        i.item_id,
        i.parent_item_id,
        i.path,
        i.name,
        i.kind,
        i.aggregate_allocated_bytes,
        i.aggregate_logical_bytes,
        i.allocated_incomplete,
        i.logical_incomplete,
        i.is_root,
        EXISTS (
          SELECT 1
          FROM items AS child
          WHERE child.scan_id = i.scan_id
            AND child.parent_item_id = i.item_id
        ),
        i.is_shared,
        i.is_hidden,
        i.is_cloud_only,
        s.scope_is_internal,
        s.scope_is_read_only,
        s.scope_is_removable
      FROM items AS i
      JOIN scans AS s ON s.id = i.scan_id
      WHERE i.scan_id = ? AND i.item_id = ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      try SQLiteDatabase.bind(itemID.uuidString, at: 2, to: statement)
      let result = sqlite3_step(statement)
      guard result != SQLITE_DONE else {
        return nil
      }
      guard result == SQLITE_ROW else {
        throw SnapshotIndexError.statementFailed(code: result)
      }
      let item = try storageTreeItem(from: statement)
      let volumeCharacteristics = ScanVolumeCharacteristics(
        isInternal: boolValue(at: 14, in: statement),
        isReadOnly: boolValue(at: 15, in: statement),
        isRemovable: boolValue(at: 16, in: statement)
      )
      return StorageItemDetail(item: item, volumeCharacteristics: volumeCharacteristics)
    }
  }

  private func directChildren(
    of parentID: UUID,
    in scan: ScanID,
    offset: Int,
    limit: Int,
    database: OpaquePointer
  ) throws -> StorageTreePage {
    guard limit > 0 else {
      return StorageTreePage(
        parentID: parentID,
        items: [],
        nextOffset: nil
      )
    }

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
        ),
        is_shared,
        is_hidden,
        is_cloud_only
      FROM items
      WHERE scan_id = ?
        AND parent_item_id = ?
        AND is_package_descendant = 0
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

  @discardableResult
  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int,
    largestItemLimit: Int = 200,
    treePageLimit: Int = 200
  ) async throws -> PromotedScanSnapshot {
    try Task.checkCancellation()
    return try withDatabase { database in
      try SQLiteDatabase.transaction(on: database) {
        try Task.checkCancellation()
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
        let largestItems = try largestItems(
          in: candidate,
          limit: largestItemLimit,
          database: database
        )
        let root = try treeRoot(
          in: candidate,
          database: database
        )
        let rootPage = try directChildren(
          of: root.id,
          in: candidate,
          offset: 0,
          limit: treePageLimit,
          database: database
        )
        let scope = try scope(for: candidate, in: database)
        let completedAt = dateProvider.now()
        let expiresAt = completedAt.addingTimeInterval(86_400)
        let completion = ScanCompletion(
          accessibleItemCount: actualItemCount,
          issueCount: actualIssueCount
        )
        let promotedSnapshot = PromotedScanSnapshot(
          scanID: candidate,
          scope: scope,
          completion: completion,
          completedAt: completedAt,
          expiresAt: expiresAt,
          largestItems: largestItems,
          treeRoot: root,
          rootPage: rootPage
        )
        try Task.checkCancellation()
        try deleteScans(with: .completed, in: database)
        try SQLiteDatabase.withStatement(
          """
          UPDATE scans
          SET status = ?,
              completed_at = ?,
              expires_at = ?,
              snapshot_schema_version = 1
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
              completedAt.timeIntervalSince1970
            )
          )
          try SQLiteDatabase.requireSuccess(
            sqlite3_bind_double(
              statement,
              3,
              expiresAt.timeIntervalSince1970
            )
          )
          try SQLiteDatabase.bind(
            candidate.rawValue.uuidString,
            at: 4,
            to: statement
          )
          try SQLiteDatabase.bind(
            ScanStatus.candidate.rawValue,
            at: 5,
            to: statement
          )
          try SQLiteDatabase.requireDone(statement)
          guard sqlite3_changes(database) == 1 else {
            throw SnapshotIndexError.candidateNotFound
          }
        }
        try Task.checkCancellation()
        return promotedSnapshot
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

  private func reconstructDatabase() throws {
    let fileManager = FileManager.default
    for fileURL in [
      databaseURL,
      URL(fileURLWithPath: "\(databaseURL.path)-journal"),
      URL(fileURLWithPath: "\(databaseURL.path)-wal"),
      URL(fileURLWithPath: "\(databaseURL.path)-shm"),
    ] {
      do {
        try fileManager.removeItem(at: fileURL)
      } catch let error as CocoaError where error.code == .fileNoSuchFile {
        continue
      }
    }
    try withDatabase { _ in () }
  }

  private func shouldReconstruct(for error: Error) -> Bool {
    switch error {
    case SnapshotIndexError.incompatibleSchema,
      SnapshotIndexError.databaseIntegrityCheckFailed,
      SnapshotIndexError.invalidSnapshotMetadata:
      return true
    case SnapshotIndexError.openFailed(let code),
      SnapshotIndexError.statementFailed(let code):
      let primaryCode = code & 0xFF
      return primaryCode == SQLITE_CORRUPT || primaryCode == SQLITE_NOTADB
    default:
      return false
    }
  }

  private func createSchema(in database: OpaquePointer) throws {
    let version = try schemaVersion(in: database)
    if version == 0, try !databaseObjectExists(named: "scans", in: database) {
      try SQLiteDatabase.transaction(on: database) {
        try createVersionFourSchema(in: database)
      }
      return
    }

    if version == 4 {
      guard try hasVersionFourSchema(in: database) else {
        throw SnapshotIndexError.incompatibleSchema
      }
      return
    }

    guard (1...3).contains(version) else {
      throw SnapshotIndexError.incompatibleSchema
    }

    try SQLiteDatabase.transaction(on: database) {
      try ensureScanColumns(in: database)
      try deleteScans(with: .candidate, in: database)
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
        """,
        on: database
      )
      try deleteCompletedSnapshotsWithoutStableScope(in: database)
      try setSchemaVersion(4, in: database)
    }
  }

  private func createVersionFourSchema(in database: OpaquePointer) throws {
    try SQLiteDatabase.execute(
      """
      CREATE TABLE IF NOT EXISTS scans (
        id TEXT PRIMARY KEY NOT NULL,
        scope_path TEXT NOT NULL,
        status INTEGER NOT NULL,
        started_at REAL NOT NULL,
        completed_at REAL,
        scope_kind INTEGER NOT NULL,
        scope_volume_identity TEXT NOT NULL,
        scope_is_internal INTEGER,
        scope_is_read_only INTEGER,
        scope_is_removable INTEGER,
        snapshot_schema_version INTEGER,
        expires_at REAL
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
        is_package_descendant INTEGER NOT NULL DEFAULT 0,
        file_system_identity TEXT,
        hard_link_count INTEGER,
        is_shared INTEGER NOT NULL DEFAULT 0,
        is_cloud_only INTEGER NOT NULL DEFAULT 0,
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

      """,
      on: database
    )
    try setSchemaVersion(4, in: database)
  }

  private func ensureScanColumns(in database: OpaquePointer) throws {
    let columns = try scanColumnNames(in: database)
    let requiredColumns: [(name: String, definition: String)] = [
      ("scope_kind", "INTEGER"),
      ("scope_volume_identity", "TEXT"),
      ("scope_is_internal", "INTEGER"),
      ("scope_is_read_only", "INTEGER"),
      ("scope_is_removable", "INTEGER"),
      ("snapshot_schema_version", "INTEGER"),
      ("expires_at", "REAL"),
    ]

    for column in requiredColumns where !columns.contains(column.name) {
      try SQLiteDatabase.execute(
        "ALTER TABLE scans ADD COLUMN \(column.name) \(column.definition);",
        on: database
      )
    }
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
      ("is_package_descendant", "INTEGER NOT NULL DEFAULT 0"),
      ("file_system_identity", "TEXT"),
      ("hard_link_count", "INTEGER"),
      ("is_shared", "INTEGER NOT NULL DEFAULT 0"),
      ("is_cloud_only", "INTEGER NOT NULL DEFAULT 0"),
    ]

    for column in requiredColumns where !columns.contains(column.name) {
      try SQLiteDatabase.execute(
        "ALTER TABLE items ADD COLUMN \(column.name) \(column.definition);",
        on: database
      )
    }
  }

  private func scope(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws -> ScanScope {
    try SQLiteDatabase.withStatement(
      """
      SELECT
        scope_path,
        scope_kind,
        scope_volume_identity,
        scope_is_internal,
        scope_is_read_only,
        scope_is_removable
      FROM scans
      WHERE id = ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      guard
        sqlite3_step(statement) == SQLITE_ROW,
        let scopePath = sqlite3_column_text(statement, 0),
        let kind = ScanScope.Kind(
          persistedValue: Int(sqlite3_column_int64(statement, 1))
        ),
        let volumeIdentity = sqlite3_column_text(statement, 2)
      else {
        throw SnapshotIndexError.integrityCheckFailed
      }

      return ScanScope(
        kind: kind,
        location: URL(fileURLWithPath: String(cString: scopePath)),
        volumeIdentity: ScanVolumeIdentity(
          rawValue: String(cString: volumeIdentity)
        ),
        volumeCharacteristics: ScanVolumeCharacteristics(
          isInternal: boolValue(at: 3, in: statement),
          isReadOnly: boolValue(at: 4, in: statement),
          isRemovable: boolValue(at: 5, in: statement)
        )
      )
    }
  }

  private func boolValue(
    at index: Int32,
    in statement: OpaquePointer
  ) -> Bool? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    return sqlite3_column_int64(statement, index) != 0
  }

  private func itemColumnNames(in database: OpaquePointer) throws -> Set<String> {
    try columnNames(in: "items", database: database)
  }

  private func scanColumnNames(in database: OpaquePointer) throws -> Set<String> {
    try columnNames(in: "scans", database: database)
  }

  private func columnNames(
    in table: String,
    database: OpaquePointer
  ) throws -> Set<String> {
    try SQLiteDatabase.withStatement(
      "PRAGMA table_info(\(table));",
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

  private func deleteCompletedSnapshotsWithoutStableScope(
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      DELETE FROM scans
      WHERE status = ?
        AND (
          scope_kind IS NULL
          OR scope_volume_identity IS NULL
          OR trim(scope_volume_identity) = ''
        );
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(ScanStatus.completed.rawValue, at: 1, to: statement)
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func schemaVersion(in database: OpaquePointer) throws -> Int {
    try SQLiteDatabase.withStatement(
      "PRAGMA user_version;",
      on: database
    ) { statement in
      let result = sqlite3_step(statement)
      guard result == SQLITE_ROW else {
        throw SnapshotIndexError.statementFailed(code: result)
      }
      return Int(sqlite3_column_int64(statement, 0))
    }
  }

  private func hasVersionFourSchema(in database: OpaquePointer) throws -> Bool {
    guard
      try databaseTableExists(named: "scans", in: database),
      try databaseTableExists(named: "items", in: database),
      try databaseTableExists(named: "scan_issues", in: database)
    else {
      return false
    }
    let requiredScanColumns: Set<String> = [
      "id",
      "scope_path",
      "status",
      "started_at",
      "completed_at",
      "scope_kind",
      "scope_volume_identity",
      "scope_is_internal",
      "scope_is_read_only",
      "scope_is_removable",
      "snapshot_schema_version",
      "expires_at",
    ]
    let requiredItemColumns: Set<String> = [
      "scan_id",
      "item_id",
      "parent_path",
      "parent_item_id",
      "path",
      "name",
      "kind",
      "allocated_bytes",
      "logical_bytes",
      "is_hidden",
      "is_root",
      "tree_depth",
      "aggregate_allocated_bytes",
      "aggregate_logical_bytes",
      "allocated_incomplete",
      "logical_incomplete",
      "is_package_descendant",
      "file_system_identity",
      "hard_link_count",
      "is_shared",
      "is_cloud_only",
    ]
    let requiredIssueColumns: Set<String> = [
      "scan_id",
      "path",
      "kind",
      "message",
    ]
    let scanColumns = try scanColumnNames(in: database)
    let itemColumns = try itemColumnNames(in: database)
    let issueColumns = try columnNames(in: "scan_issues", database: database)
    return requiredScanColumns.isSubset(of: scanColumns)
      && requiredItemColumns.isSubset(of: itemColumns)
      && requiredIssueColumns.isSubset(of: issueColumns)
  }

  private func databaseTableExists(
    named name: String,
    in database: OpaquePointer
  ) throws -> Bool {
    try SQLiteDatabase.withStatement(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(name, at: 1, to: statement)
      let result = sqlite3_step(statement)
      switch result {
      case SQLITE_ROW:
        return true
      case SQLITE_DONE:
        return false
      default:
        throw SnapshotIndexError.statementFailed(code: result)
      }
    }
  }

  private func setSchemaVersion(
    _ version: Int,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.execute(
      "PRAGMA user_version = \(version);",
      on: database
    )
  }

  private func databaseObjectExists(
    named name: String,
    in database: OpaquePointer
  ) throws -> Bool {
    try SQLiteDatabase.withStatement(
      "SELECT 1 FROM sqlite_master WHERE name = ? LIMIT 1;",
      on: database
    ) { statement in
      try SQLiteDatabase.bind(name, at: 1, to: statement)
      let result = sqlite3_step(statement)
      switch result {
      case SQLITE_ROW:
        return true
      case SQLITE_DONE:
        return false
      default:
        throw SnapshotIndexError.statementFailed(code: result)
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
    try Task.checkCancellation()
    try resolveParentIDs(for: scan, in: database)
    try Task.checkCancellation()
    try assignTreeDepths(for: scan, in: database)
    try Task.checkCancellation()
    try markPackageDescendants(for: scan, in: database)
    try Task.checkCancellation()
    try initializeAggregates(for: scan, in: database)
    try Task.checkCancellation()
    let maximumDepth = try maxTreeDepth(for: scan, in: database)
    for depth in stride(from: maximumDepth, through: 0, by: -1) {
      try Task.checkCancellation()
      try aggregateFolders(
        at: depth,
        for: scan,
        in: database
      )
    }
    try Task.checkCancellation()
    try aggregateAllocatedBytes(for: scan, in: database)
    try Task.checkCancellation()
    try markIssueAncestorsIncomplete(for: scan, in: database)
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
          AND rtrim(parent.path, '/') = rtrim(items.parent_path, '/')
          AND parent.kind IN (?, ?)
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
        StorageItemKind.package.rawValue,
        at: 2,
        to: statement
      )
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 3, to: statement)
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

  private func markPackageDescendants(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      UPDATE items
      SET is_package_descendant = CASE WHEN EXISTS (
          SELECT 1
          FROM items AS package
          WHERE package.scan_id = items.scan_id
            AND package.kind = ?
            AND package.item_id = items.parent_item_id
        ) THEN 1 ELSE 0 END
      WHERE scan_id = ?;
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 1,
        to: statement
      )
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 2, to: statement)
      try SQLiteDatabase.requireDone(statement)
    }

    while true {
      try SQLiteDatabase.withStatement(
        """
        UPDATE items
        SET is_package_descendant = 1
        WHERE scan_id = ?
          AND is_package_descendant = 0
          AND EXISTS (
            SELECT 1
            FROM items AS parent
            WHERE parent.scan_id = items.scan_id
              AND parent.item_id = items.parent_item_id
              AND parent.is_package_descendant = 1
          );
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
      guard sqlite3_changes(database) > 0 else {
        break
      }
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
      try Task.checkCancellation()
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
            WHEN kind IN (?, ?) THEN NULL
            ELSE allocated_bytes
          END,
          aggregate_logical_bytes = CASE
            WHEN kind IN (?, ?) THEN NULL
            ELSE logical_bytes
          END,
          allocated_incomplete = CASE
            WHEN kind NOT IN (?, ?) AND allocated_bytes IS NULL THEN 1
            ELSE 0
          END,
          logical_incomplete = CASE
            WHEN kind NOT IN (?, ?) AND logical_bytes IS NULL THEN 1
            ELSE 0
          END,
          is_shared = CASE
            WHEN kind NOT IN (?, ?)
              AND file_system_identity IS NOT NULL
              AND hard_link_count > 1
              THEN 1
            ELSE 0
          END
      WHERE scan_id = ?;
      """,
      on: database
    ) { statement in
      for index in stride(from: 1, through: 8, by: 2) {
        try SQLiteDatabase.bind(
          StorageItemKind.folder.rawValue,
          at: Int32(index),
          to: statement
        )
        try SQLiteDatabase.bind(
          StorageItemKind.package.rawValue,
          at: Int32(index + 1),
          to: statement
        )
      }
      try SQLiteDatabase.bind(
        StorageItemKind.folder.rawValue,
        at: 9,
        to: statement
      )
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 10,
        to: statement
      )
      try SQLiteDatabase.bind(
        scan.rawValue.uuidString,
        at: 11,
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
        AND EXISTS (
          SELECT 1
          FROM scan_issues AS issue
          WHERE issue.scan_id = items.scan_id
            AND (
              issue.path = rtrim(items.path, '/')
              OR (
                rtrim(items.path, '/') = ''
                AND substr(issue.path, 1, 1) = '/'
              )
              OR substr(
                issue.path,
                1,
                length(rtrim(items.path, '/')) + 1
              ) = rtrim(items.path, '/') || '/'
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
      SET aggregate_logical_bytes = (
            SELECT SUM(child.aggregate_logical_bytes)
            FROM items AS child
            WHERE child.scan_id = items.scan_id
              AND child.parent_item_id = items.item_id
          ),
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
          END,
          is_shared = CASE
            WHEN is_shared = 1 OR EXISTS (
              SELECT 1
              FROM items AS child
              WHERE child.scan_id = items.scan_id
                AND child.parent_item_id = items.item_id
                AND child.is_shared = 1
            )
            THEN 1
            ELSE 0
          END,
          is_cloud_only = CASE
            WHEN is_cloud_only = 1 OR EXISTS (
              SELECT 1
              FROM items AS child
              WHERE child.scan_id = items.scan_id
                AND child.parent_item_id = items.item_id
                AND child.is_cloud_only = 1
            )
            THEN 1
            ELSE 0
          END
      WHERE scan_id = ? AND kind IN (?, ?) AND tree_depth = ?;
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
      try SQLiteDatabase.bind(
        StorageItemKind.package.rawValue,
        at: 3,
        to: statement
      )
      try SQLiteDatabase.bind(depth, at: 4, to: statement)
      try SQLiteDatabase.requireDone(statement)
    }
  }

  private func aggregateAllocatedBytes(
    for scan: ScanID,
    in database: OpaquePointer
  ) throws {
    try SQLiteDatabase.withStatement(
      """
      WITH RECURSIVE descendants(ancestor_id, item_id) AS (
        SELECT parent.item_id, child.item_id
        FROM items AS parent
        JOIN items AS child
          ON child.scan_id = parent.scan_id
         AND child.parent_item_id = parent.item_id
        WHERE parent.scan_id = ? AND parent.kind IN (?, ?)
        UNION ALL
        SELECT descendants.ancestor_id, child.item_id
        FROM descendants
        JOIN items AS child
          ON child.scan_id = ?
         AND child.parent_item_id = descendants.item_id
      ),
      allocation_groups AS (
        SELECT
          descendants.ancestor_id,
          CASE
            WHEN leaf.file_system_identity IS NOT NULL
              AND leaf.hard_link_count > 1
              THEN leaf.file_system_identity
            ELSE leaf.item_id
          END AS allocation_key,
          MAX(leaf.allocated_bytes) AS allocated_bytes,
          MAX(CASE WHEN leaf.allocated_bytes IS NULL THEN 1 ELSE 0 END)
            AS is_incomplete
        FROM descendants
        JOIN items AS leaf
          ON leaf.scan_id = ? AND leaf.item_id = descendants.item_id
        WHERE leaf.kind NOT IN (?, ?)
        GROUP BY descendants.ancestor_id, allocation_key
      ),
      totals AS (
        SELECT
          ancestor_id,
          SUM(allocated_bytes) AS allocated_bytes,
          MAX(is_incomplete) AS is_incomplete
        FROM allocation_groups
        GROUP BY ancestor_id
      )
      UPDATE items
      SET aggregate_allocated_bytes = (
            SELECT totals.allocated_bytes
            FROM totals
            WHERE totals.ancestor_id = items.item_id
          ),
          allocated_incomplete = CASE
            WHEN allocated_incomplete = 1 OR COALESCE((
              SELECT totals.is_incomplete
              FROM totals
              WHERE totals.ancestor_id = items.item_id
            ), 0) = 1
            THEN 1
            ELSE 0
          END
      WHERE scan_id = ? AND kind IN (?, ?);
      """,
      on: database
    ) { statement in
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.folder.rawValue, at: 2, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.package.rawValue, at: 3, to: statement)
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 4, to: statement)
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 5, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.folder.rawValue, at: 6, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.package.rawValue, at: 7, to: statement)
      try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 8, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.folder.rawValue, at: 9, to: statement)
      try SQLiteDatabase.bind(StorageItemKind.package.rawValue, at: 10, to: statement)
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
      hasChildren: kind == .folder && sqlite3_column_int64(statement, 10) != 0,
      isRoot: isRoot,
      isShared: sqlite3_column_int64(statement, 11) != 0,
      isHidden: sqlite3_column_int64(statement, 12) != 0,
      isCloudOnly: sqlite3_column_int64(statement, 13) != 0
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
      var sawResult = false
      while true {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
          sawResult = true
          guard
            let resultText = sqlite3_column_text(statement, 0),
            String(cString: resultText) == "ok"
          else {
            throw SnapshotIndexError.databaseIntegrityCheckFailed
          }
        case SQLITE_DONE:
          guard sawResult else {
            throw SnapshotIndexError.databaseIntegrityCheckFailed
          }
          return
        default:
          throw SnapshotIndexError.statementFailed(code: result)
        }
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
        is_hidden,
        file_system_identity,
        hard_link_count,
        is_cloud_only
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        try SQLiteDatabase.bind(
          item.fileSystemIdentity?.uuidString,
          at: 10,
          to: statement
        )
        try SQLiteDatabase.bind(
          item.hardLinkCount.flatMap(Int64.init(exactly:)),
          at: 11,
          to: statement
        )
        try SQLiteDatabase.bind(item.isCloudOnly ? 1 : 0, at: 12, to: statement)
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

extension ScanScope.Kind {
  fileprivate var persistedValue: Int {
    switch self {
    case .homeFolder:
      0
    case .entireInternalDisk:
      1
    case .custom:
      2
    }
  }

  fileprivate init?(persistedValue: Int) {
    switch persistedValue {
    case 0:
      self = .homeFolder
    case 1:
      self = .entireInternalDisk
    case 2:
      self = .custom
    default:
      return nil
    }
  }
}
