import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

struct ResponseMessageConversionsTests {
  @Test("Response messages convert to model messages in order")
  func responseMessagesAsModelMessages() {
    let assistant = ResponseMessage.assistant(
      AssistantModelMessage(content: .text("hi"))
    )
    let tool = ResponseMessage.tool(
      ToolModelMessage(content: [])
    )

    let modelMessages = [assistant, tool].asModelMessages()

    #expect(modelMessages.count == 2)
    if case .assistant(let value) = modelMessages[0] {
      #expect(value.content == .text("hi"))
    } else {
      Issue.record("Expected assistant message at index 0")
    }
    if case .tool(let value) = modelMessages[1] {
      #expect(value.content.isEmpty)
    } else {
      Issue.record("Expected tool message at index 1")
    }
  }

  @Test("Array plus operators accept ResponseMessage combinations")
  func responseMessagesPlusModelMessages() {
    let assistant = ResponseMessage.assistant(
      AssistantModelMessage(content: .text("A"))
    )

    let lhs = [assistant]
    let rhs: [ModelMessage] = [.system("S")]

    let merged = lhs + rhs
    #expect(merged.count == 2)
    if case .assistant(let value) = merged[0] {
      #expect(value.content == .text("A"))
    } else {
      Issue.record("Expected assistant at index 0")
    }
    if case .system(let value) = merged[1] {
      #expect(value.content == "S")
    } else {
      Issue.record("Expected system at index 1")
    }

    let mergedReverse = rhs + lhs
    #expect(mergedReverse.count == 2)
    if case .system(let value) = mergedReverse[0] {
      #expect(value.content == "S")
    } else {
      Issue.record("Expected system at index 0")
    }
  }

  @Test("Response + user operator keeps order")
  func responseMessagesPlusUser() {
    let assistant = ResponseMessage.assistant(
      AssistantModelMessage(content: .text("first"))
    )

    let result = [assistant] + [.user("follow up")]
    #expect(result.count == 2)
    if case .assistant(let value) = result[0] {
      #expect(value.content == .text("first"))
    } else {
      Issue.record("Expected assistant at index 0")
    }
    if case .user(let value) = result[1],
       case .text(let text) = value.content {
      #expect(text == "follow up")
    } else {
      Issue.record("Expected user text at index 1")
    }
  }

  @Test("convertModelMessagesToResponseMessages drops system/user")
  func modelToResponseDropsNonConvertibleRoles() {
    let messages: [ModelMessage] = [
      .system("system"),
      .user("user"),
      .assistant("assistant"),
      .tool(ToolModelMessage(content: []))
    ]

    let responses = convertModelMessagesToResponseMessages(messages)
    #expect(responses.count == 2)
    if case .assistant(let value) = responses.first {
      #expect(value.content == .text("assistant"))
    } else {
      Issue.record("Expected assistant response")
    }
    if case .tool = responses.last {
      // ok
    } else {
      Issue.record("Expected tool response")
    }
  }

  @Test("ModelMessage convenience constructors produce expected roles")
  func modelMessageConvenience() {
    let system = ModelMessage.system("guide")
    let user = ModelMessage.user("hello")
    let assistant = ModelMessage.assistant("hi")

    if case .system(let value) = system {
      #expect(value.content == "guide")
    } else {
      Issue.record("Expected system builder")
    }
    if case .user(let value) = user,
       case .text(let text) = value.content {
      #expect(text == "hello")
    } else {
      Issue.record("Expected user text builder")
    }
    if case .assistant(let value) = assistant {
      #expect(value.content == .text("hi"))
    } else {
      Issue.record("Expected assistant builder")
    }
  }
}
