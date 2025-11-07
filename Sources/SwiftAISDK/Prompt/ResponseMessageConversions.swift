import AISDKProvider
import AISDKProviderUtils

@inlinable
public func convertResponseMessagesToModelMessages(
  _ messages: [ResponseMessage]
) -> [ModelMessage] {
  messages.map { message in
    switch message {
    case .assistant(let assistant):
      return .assistant(assistant)
    case .tool(let tool):
      return .tool(tool)
    }
  }
}

@inlinable
public func convertModelMessagesToResponseMessages(
  _ messages: [ModelMessage]
) -> [ResponseMessage] {
  messages.compactMap { message in
    switch message {
    case .assistant(let assistant):
      return .assistant(assistant)
    case .tool(let tool):
      return .tool(tool)
    case .system, .user:
      return nil
    }
  }
}

public extension Array where Element == ResponseMessage {
  @inlinable
  func asModelMessages() -> [ModelMessage] {
    convertResponseMessagesToModelMessages(self)
  }
}

@inlinable
public func + (
  lhs: [ResponseMessage],
  rhs: [ModelMessage]
) -> [ModelMessage] {
  convertResponseMessagesToModelMessages(lhs) + rhs
}

@inlinable
public func + (
  lhs: [ModelMessage],
  rhs: [ResponseMessage]
) -> [ModelMessage] {
  lhs + convertResponseMessagesToModelMessages(rhs)
}
