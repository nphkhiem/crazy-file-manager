import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Adaptive Layout")
struct AdaptiveLayoutTests {
  @Test
  func givenAWidthAboveTheBreakpoint_whenInspectorOverlayIsResolved_thenTheInspectorStaysInline() {
    #expect(!ResultsView.isInspectorOverlay(forWidth: 1_180))
  }

  @Test
  func
    givenAWidthAtTheMinimumWindowSize_whenInspectorOverlayIsResolved_thenTheInspectorBecomesAnOverlay()
  {
    #expect(ResultsView.isInspectorOverlay(forWidth: 900))
  }

  @Test
  func
    givenAWidthExactlyAtTheBreakpoint_whenInspectorOverlayIsResolved_thenTheInspectorStaysInline()
  {
    #expect(!ResultsView.isInspectorOverlay(forWidth: ResultsView.inspectorOverlayBreakpoint))
  }
}
