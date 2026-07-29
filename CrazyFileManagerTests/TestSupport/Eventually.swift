import Testing

@MainActor
func eventually(
  attempts: Int = 200,
  condition: @MainActor () async -> Bool
) async {
  for _ in 0..<attempts {
    if await condition() {
      return
    }
    await Task.yield()
  }

  Issue.record("Condition did not become true within the bounded attempts")
}
