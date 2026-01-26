import ExamplesCore
import OpenAIProvider
import SwiftAISDK

struct StreamTextOpenAIResponsesMCPToolExample: Example {
  static let name = "stream-text/openai-responses-mcp-tool"
  static let description = "OpenAI Responses provider-executed MCP tool calls (with approvals)."

  static func run() async throws {
    guard (try? EnvLoader.require("OPENAI_API_KEY")) != nil else {
      Logger.warning("Skipping network call: missing OPENAI_API_KEY")
      return
    }

    let serverUrl = EnvLoader.get("OPENAI_MCP_SERVER_URL")
    let resolvedServerUrl = serverUrl.isEmpty ? "https://zip1.io/mcp" : serverUrl

    do {
      let mcp = openai.tools.mcp(.init(
        serverLabel: "zip1",
        serverUrl: resolvedServerUrl,
        serverDescription: "Link shortener",
        requireApproval: .always
      ))

      let result = try streamText(
        model: openai.responses("gpt-5"),
        system:
          "You are a helpful assistant that can shorten links. " +
          "Use the MCP tools available to you to shorten links when needed. " +
          "When a tool execution is not approved by the user, do not retry it. " +
          "Just say that the tool execution was not approved.",
        prompt: "Shorten https://openai.com and return only the shortened URL.",
        tools: [
          "mcp": mcp
        ],
        toolChoice: .tool(toolName: "mcp"),
        experimentalApprove: { request in
          Logger.info("approve MCP tool: \(request.toolCall.toolName)")
          return .approve
        },
        stopWhen: [stepCountIs(4)]
      )

      for try await part in result.fullStream {
        switch part {
        case .textDelta(_, let delta, _):
          print(delta, terminator: "")

        case .toolCall(let call):
          Logger.section("TOOL CALL \(call.toolName)")
          Helpers.printJSON(call.input)

        case .toolResult(let result):
          Logger.section("TOOL RESULT \(result.toolName)")
          Helpers.printJSON(result.output)

        case .finishStep(_, let usage, let finishReason, _):
          Logger.section("STEP FINISH")
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Helpers.printJSON(usage)
          print("")

        case .finish(let finishReason, let totalUsage):
          Logger.section("FINISH")
          Logger.info("Finish reason: \(finishReason.rawValue)")
          Helpers.printJSON(totalUsage)

        case .error(let error):
          Logger.error(error.localizedDescription)

        default:
          continue
        }
      }
      print("")
    } catch {
      Logger.warning("Skipping network call: \(error.localizedDescription)")
    }
  }
}

