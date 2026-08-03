import Foundation

enum SessionActivityKind: Equatable, Sendable {
  case rename
  case trash
}

enum SessionActivityOutcome: Equatable, Sendable {
  case succeeded
  case rejected(reason: String)
}

struct SessionActivityEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  let kind: SessionActivityKind
  let itemName: String
  let outcome: SessionActivityOutcome
  let occurredAt: Date
}
