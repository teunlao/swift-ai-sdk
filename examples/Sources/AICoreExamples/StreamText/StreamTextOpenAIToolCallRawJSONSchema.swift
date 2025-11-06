import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIToolCallRawJSONSchemaExample: Example {
  static let name = "stream-text/openai-tool-call-raw-json-schema"
  static let description = "Define tool with raw JSON Schema via FlexibleSchema(jsonSchema:)."

  static func run() async throws {
    do {
      // Raw JSON schema for { text: string }
      let inputSchema: FlexibleSchema<JSONValue> = FlexibleSchema(
        jsonSchema(JSONValue.object([
          "type": JSONValue.string("object"),
          "required": JSONValue.array([JSONValue.string("text")]),
          "properties": JSONValue.object([
            "text": JSONValue.object(["type": JSONValue.string("string")])
          ])
        ]))
      )

      let outputSchema: FlexibleSchema<JSONValue> = FlexibleSchema(
        jsonSchema(JSONValue.object([
          "type": JSONValue.string("object"),
          "required": JSONValue.array([JSONValue.string("upper")]),
          "properties": JSONValue.object([
            "upper": JSONValue.object(["type": JSONValue.string("string")])
          ])
        ]))
      )

      let uppercase = AISDKProviderUtils.tool(
        description: "Return uppercased text",
        inputSchema: inputSchema,
        execute: { (json, _) in
          guard case JSONValue.object(let obj) = json, case JSONValue.string(let text)? = obj["text"] else {
          return .value(JSONValue.object(["upper": JSONValue.string("")]))
          }
          return .value(JSONValue.object(["upper": JSONValue.string(text.uppercased())]))
        },
        outputSchema: outputSchema
      )

      let result = try streamText(
        model: try openai("gpt-5-mini"),
        prompt: "Use the uppercase tool to transform 'swift ai sdk' into uppercase.",
        tools: ["uppercase": uppercase]
      )

      for try await part in result.fullStream {
        switch part {
        case .toolResult(let res):
          Logger.info("toolResult: \(res.output)")
        case .textDelta(_, let delta, _):
          print(delta, terminator: "")
        default:
          break
        }
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}
