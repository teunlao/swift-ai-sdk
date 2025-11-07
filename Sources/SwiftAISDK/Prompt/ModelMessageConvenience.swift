import AISDKProvider
import AISDKProviderUtils

public extension ModelMessage {
  @inlinable
  static func user(
    _ text: String,
    providerOptions: ProviderOptions? = nil
  ) -> ModelMessage {
    .user(UserModelMessage(content: .text(text), providerOptions: providerOptions))
  }

  @inlinable
  static func system(
    _ text: String,
    providerOptions: ProviderOptions? = nil
  ) -> ModelMessage {
    .system(SystemModelMessage(content: text, providerOptions: providerOptions))
  }

  @inlinable
  static func assistant(
    _ text: String,
    providerOptions: ProviderOptions? = nil
  ) -> ModelMessage {
    .assistant(AssistantModelMessage(content: .text(text), providerOptions: providerOptions))
  }
}
