import Testing

@testable import CrazyFileManager

@Suite("App Version")
struct AppVersionTests {
  @Test
  func givenADotSeparatedVersionString_whenParsed_thenComponentsMatch() {
    let version = AppVersion("1.2.3")

    #expect(version?.components == [1, 2, 3])
  }

  @Test
  func givenTwoVersions_whenCompared_thenTheOneWithTheHigherComponentIsGreater() {
    let older = AppVersion("1.2.3")!
    let newer = AppVersion("1.3.0")!

    #expect(older < newer)
    #expect(!(newer < older))
  }

  @Test
  func givenAMalformedVersionString_whenParsed_thenInitReturnsNil() {
    #expect(AppVersion("1.2.x") == nil)
    #expect(AppVersion("") == nil)
  }
}
