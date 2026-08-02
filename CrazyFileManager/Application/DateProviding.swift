import Foundation

protocol DateProviding: Sendable {
  func now() -> Date
}

struct SystemDateProvider: DateProviding {
  func now() -> Date {
    Date()
  }
}
