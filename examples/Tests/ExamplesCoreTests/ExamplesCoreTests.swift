import ExamplesCore
import Foundation
import Testing

@Test
func envLoaderLoadsKeyValues() throws {
  let envContents = """
  FOO=bar
  QUOTED="baz"
  SINGLE='qux'
  """

  let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("env")
  try envContents.write(to: tmp, atomically: true, encoding: .utf8)
  defer { try? FileManager.default.removeItem(at: tmp) }

  try EnvLoader.load(from: tmp.path)

  #expect(String(cString: getenv("FOO")!) == "bar")
  #expect(String(cString: getenv("QUOTED")!) == "baz")
  #expect(String(cString: getenv("SINGLE")!) == "qux")
}

@Test
func helpersTruncate() {
  #expect(Helpers.truncate("hello", to: 10) == "hello")
  #expect(Helpers.truncate("hello world", to: 8) == "hello...")
}

@Test
func helpersFormatDuration() {
  #expect(Helpers.formatDuration(0.05) == "50ms")
  #expect(Helpers.formatDuration(1.234) == "1.23s")
}
