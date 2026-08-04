import Foundation
import SQLite3

enum SnapshotIndexError: Error, Equatable {
  case openFailed(code: Int32)
  case statementFailed(code: Int32)
  case incompatibleSchema
  case databaseIntegrityCheckFailed
  case invalidSnapshotMetadata
  case candidateNotFound
  case orphanedItemCount(actual: Int)
  case itemCountMismatch(expected: Int, actual: Int)
  case issueCountMismatch(expected: Int, actual: Int)
  case integrityCheckFailed
}

enum SQLiteDatabase {
  static func withConnection<Result>(
    at databaseURL: URL,
    operation: (OpaquePointer) throws -> Result
  ) throws -> Result {
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var database: OpaquePointer?
    let openResult = sqlite3_open_v2(
      databaseURL.path(percentEncoded: false),
      &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard openResult == SQLITE_OK, let database else {
      if let database {
        sqlite3_close(database)
      }
      throw SnapshotIndexError.openFailed(code: openResult)
    }
    defer {
      sqlite3_close(database)
    }

    try execute("PRAGMA foreign_keys = ON;", on: database)
    return try operation(database)
  }

  static func execute(_ sql: String, on database: OpaquePointer) throws {
    let result = sqlite3_exec(database, sql, nil, nil, nil)
    guard result == SQLITE_OK else {
      throw SnapshotIndexError.statementFailed(code: result)
    }
  }

  static func transaction<Result>(
    on database: OpaquePointer,
    operation: () throws -> Result
  ) throws -> Result {
    try execute("BEGIN IMMEDIATE;", on: database)
    do {
      let result = try operation()
      try execute("COMMIT;", on: database)
      return result
    } catch {
      try? execute("ROLLBACK;", on: database)
      throw error
    }
  }

  static func withStatement<Result>(
    _ sql: String,
    on database: OpaquePointer,
    operation: (OpaquePointer) throws -> Result
  ) throws -> Result {
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else {
      throw SnapshotIndexError.statementFailed(code: result)
    }
    defer {
      sqlite3_finalize(statement)
    }
    return try operation(statement)
  }

  static func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
    let result: Int32
    if let value {
      result = value.withCString {
        sqlite3_bind_text(
          statement,
          index,
          $0,
          -1,
          unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
      }
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    try requireSuccess(result)
  }

  static func bind(_ value: Int64?, at index: Int32, to statement: OpaquePointer) throws {
    let result: Int32
    if let value {
      result = sqlite3_bind_int64(statement, index, value)
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    try requireSuccess(result)
  }

  static func bind(_ value: Int, at index: Int32, to statement: OpaquePointer) throws {
    try requireSuccess(sqlite3_bind_int64(statement, index, Int64(value)))
  }

  static func bind(_ value: Double?, at index: Int32, to statement: OpaquePointer) throws {
    let result: Int32
    if let value {
      result = sqlite3_bind_double(statement, index, value)
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    try requireSuccess(result)
  }

  static func requireDone(_ statement: OpaquePointer) throws {
    let result = sqlite3_step(statement)
    guard result == SQLITE_DONE else {
      throw SnapshotIndexError.statementFailed(code: result)
    }
  }

  static func requireSuccess(_ result: Int32) throws {
    guard result == SQLITE_OK else {
      throw SnapshotIndexError.statementFailed(code: result)
    }
  }
}
