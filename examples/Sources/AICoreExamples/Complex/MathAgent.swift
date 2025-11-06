import ExamplesCore
import OpenAIProvider
import SwiftAISDK
import Foundation

// Mirrors ai-core/src/complex/math-agent examples in Swift.

struct MathAgentExample: Example {
  static let name = "complex/math-agent"
  static let description = "Multi-step math with a calculate tool and onStepFinish."

  private struct CalcInput: Codable, Sendable { let expression: String }

  private static func evaluate(_ expr: String) throws -> Double {
    // Minimal safe evaluator: allow digits, ops, dot, spaces, parentheses
    let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
    guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      throw NSError(domain: "MathAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported characters in expression"])
    }
    // NSExpression handles basic arithmetic
    let ns = NSExpression(format: expr)
    guard let num = ns.expressionValue(with: nil, context: nil) as? NSNumber else {
      throw NSError(domain: "MathAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to evaluate expression"])
    }
    return num.doubleValue
  }

  static func run() async throws {
    let calculate = tool(
      description: "Evaluate a basic arithmetic expression (use +, -, *, /).",
      inputSchema: CalcInput.self,
      execute: { (input, _) in
        let value = try evaluate(input.expression)
        return value
      }
    )

    let prompt = [
      "A taxi driver earns $9461 per 1-hour work.",
      "If he works 12 hours a day and in 1 hour he uses 14-liters petrol with price $134 for 1-liter.",
      "How much money does he earn in one day?",
    ].joined(separator: " ")

    Logger.section("Math Agent (auto tool choice)")
    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: ["calculate": calculate.tool],
      system: [
        "You are solving math problems.",
        "Reason step by step.",
        "Use the calculator when necessary.",
        "The calculator can only do basic arithmetic.",
        "When you give the final answer, explain how you got it.",
      ].joined(separator: " "),
      prompt: prompt,
      stopWhen: [stepCountIs(10)],
      onStepFinish: { step in
        if !step.toolResults.isEmpty {
          Logger.info("STEP RESULTS count: \(step.toolResults.count)")
        }
      }
    )

    Logger.section("Final Answer")
    Logger.info(result.text)
  }
}

struct MathAgentRequiredToolChoiceExample: Example {
  static let name = "complex/math-agent-required-tool-choice"
  static let description = "Require tool usage; final answer returned as a structured tool call."

  private struct CalcInput: Codable, Sendable { let expression: String }
  private struct AnswerStep: Codable, Sendable { let calculation: String; let reasoning: String }
  private struct FinalAnswer: Codable, Sendable { let steps: [AnswerStep]; let answer: String }

  private static func evaluate(_ expr: String) throws -> Double {
    let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
    guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      throw NSError(domain: "MathAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported characters in expression"])
    }
    let ns = NSExpression(format: expr)
    guard let num = ns.expressionValue(with: nil, context: nil) as? NSNumber else {
      throw NSError(domain: "MathAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to evaluate expression"])
    }
    return num.doubleValue
  }

  static func run() async throws {
    let calculate = tool(
      description: "Evaluate a basic arithmetic expression (use +, -, *, /).",
      inputSchema: CalcInput.self,
      execute: { (input, _) in try evaluate(input.expression) }
    )

    // The 'answer' tool: model outputs a structured final answer; no execute closure.
    let answerTool: TypedTool<FinalAnswer, FinalAnswer> = tool(
      description: "Provide the final answer and the reasoning steps.",
      inputSchema: FlexibleSchema.auto(FinalAnswer.self)
    )

    let prompt = [
      "A taxi driver earns $9461 per 1-hour work.",
      "If he works 12 hours a day and in 1 hour he uses 14-liters petrol with price $134 for 1-liter.",
      "How much money does he earn in one day?",
    ].joined(separator: " ")

    Logger.section("Math Agent (toolChoice: required)")
    let result = try await generateText(
      model: openai("gpt-4o"),
      tools: [
        "calculate": calculate.tool,
        "answer": answerTool.tool
      ],
      toolChoice: .required,
      system: [
        "You are solving math problems.",
        "Reason step by step.",
        "Use the calculator when necessary.",
        "The calculator can only do basic arithmetic.",
        "When you give the final answer, explain how you got it.",
      ].joined(separator: " "),
      prompt: prompt,
      stopWhen: [stepCountIs(10)],
      onStepFinish: { step in
        if !step.toolResults.isEmpty {
          Logger.info("STEP RESULTS count: \(step.toolResults.count)")
        }
      }
    )

    Logger.section("Final Tool Calls")
    Logger.info("Tool calls: \(result.toolCalls.count)")

    if let first = result.toolResults.first,
       let decoded: FinalAnswer = try? answerTool.decodeOutput(from: first) {
      Logger.section("Decoded Final Answer")
      Logger.info("Answer: \(decoded.answer)")
      Logger.info("Steps: \(decoded.steps.count)")
    }
  }
}
