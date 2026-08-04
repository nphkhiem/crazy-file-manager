enum ResultsMode: Equatable, Sendable {
  case tree
  case allItems
}

enum AllItemsOptionalColumn: Equatable, Sendable {
  case path
  case modifiedAt
  case apparentSize
}
