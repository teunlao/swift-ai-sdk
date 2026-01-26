import ExamplesCore

func registerAllExamples() {
  ExampleCatalog.register(WeatherToolExample.self, path: WeatherToolExample.name)

  // Middleware
  ExampleCatalog.register(MiddlewareSimulateStreamingExample.self, path: MiddlewareSimulateStreamingExample.name)
  ExampleCatalog.register(MiddlewareDefaultSettingsExample.self, path: MiddlewareDefaultSettingsExample.name)
  ExampleCatalog.register(MiddlewareGenerateTextLogMiddlewareExample.self, path: MiddlewareGenerateTextLogMiddlewareExample.name)
  ExampleCatalog.register(MiddlewareStreamTextLogMiddlewareExample.self, path: MiddlewareStreamTextLogMiddlewareExample.name)
  ExampleCatalog.register(MiddlewareGenerateTextCacheMiddlewareExample.self, path: MiddlewareGenerateTextCacheMiddlewareExample.name)
  ExampleCatalog.register(MiddlewareStreamTextRAGMiddlewareExample.self, path: MiddlewareStreamTextRAGMiddlewareExample.name)

  ExampleCatalog.register(GenerateTextOpenAIExample.self, path: GenerateTextOpenAIExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIFullResultExample.self, path: GenerateTextOpenAIFullResultExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIAudioExample.self, path: GenerateTextOpenAIAudioExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAICachedPromptTokensExample.self,
    path: GenerateTextOpenAICachedPromptTokensExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAICustomFetchExample.self, path: GenerateTextOpenAICustomFetchExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAICustomHeadersExample.self, path: GenerateTextOpenAICustomHeadersExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAILogMetadataMiddlewareExample.self,
    path: GenerateTextOpenAILogMetadataMiddlewareExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAILogprobsExample.self, path: GenerateTextOpenAILogprobsExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIMultiStepExample.self, path: GenerateTextOpenAIMultiStepExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIOnFinishExample.self, path: GenerateTextOpenAIOnFinishExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIProviderOptionsExample.self,
    path: GenerateTextOpenAIProviderOptionsExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolChoiceExample.self, path: GenerateTextOpenAIToolChoiceExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolCallExample.self, path: GenerateTextOpenAIToolCallExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIActiveToolsExample.self, path: GenerateTextOpenAIActiveToolsExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIWarningExample.self, path: GenerateTextOpenAIWarningExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAINullableToolExample.self, path: GenerateTextOpenAINullableToolExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAITimeoutExample.self, path: GenerateTextOpenAITimeoutExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolApprovalExample.self, path: GenerateTextOpenAIToolApprovalExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolApprovalDynamicExample.self,
    path: GenerateTextOpenAIToolApprovalDynamicExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolCallRawJSONSchemaExample.self,
    path: GenerateTextOpenAIToolCallRawJSONSchemaExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolCallWithContextExample.self,
    path: GenerateTextOpenAIToolCallWithContextExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIToolExecutionErrorExample.self,
    path: GenerateTextOpenAIToolExecutionErrorExample.name)
  ExampleCatalog.register(
    GenerateTextOpenAIOutputObjectExample.self, path: GenerateTextOpenAIOutputObjectExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIFullResultExample.self, path: GenerateObjectOpenAIFullResultExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIFullStreamExample.self, path: GenerateObjectOpenAIFullStreamExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIEnumExample.self, path: GenerateObjectOpenAIEnumExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIRawJSONSchemaExample.self,
    path: GenerateObjectOpenAIRawJSONSchemaExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIReasoningExample.self, path: GenerateObjectOpenAIReasoningExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIResponsesExample.self, path: GenerateObjectOpenAIResponsesExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIStructuredOutputsNameDescriptionExample.self,
    path: GenerateObjectOpenAIStructuredOutputsNameDescriptionExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIRequestBodyExample.self, path: GenerateObjectOpenAIRequestBodyExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIMultimodalExample.self, path: GenerateObjectOpenAIMultimodalExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIRequestHeadersExample.self,
    path: GenerateObjectOpenAIRequestHeadersExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIStoreGenerationFinalExample.self,
    path: GenerateObjectOpenAIStoreGenerationFinalExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAINoSchemaExample.self, path: GenerateObjectOpenAINoSchemaExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIDateParsingExample.self, path: GenerateObjectOpenAIDateParsingExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIStoreGenerationExample.self,
    path: GenerateObjectOpenAIStoreGenerationExample.name)
  ExampleCatalog.register(
    GenerateObjectOpenAIArrayExample.self, path: GenerateObjectOpenAIArrayExample.name)
  ExampleCatalog.register(GenerateObjectOpenAIExample.self, path: GenerateObjectOpenAIExample.name)
  ExampleCatalog.register(TranscribeOpenAIExample.self, path: TranscribeOpenAIExample.name)
  ExampleCatalog.register(TranscribeOpenAIURLExample.self, path: TranscribeOpenAIURLExample.name)
  ExampleCatalog.register(
    TranscribeOpenAIStringExample.self, path: TranscribeOpenAIStringExample.name)
  ExampleCatalog.register(
    TranscribeOpenAIVerboseExample.self, path: TranscribeOpenAIVerboseExample.name)
  ExampleCatalog.register(TranscribeDeepgramExample.self, path: TranscribeDeepgramExample.name)
  ExampleCatalog.register(
    TranscribeDeepgramURLExample.self, path: TranscribeDeepgramURLExample.name)
  ExampleCatalog.register(
    TranscribeDeepgramStringExample.self, path: TranscribeDeepgramStringExample.name)
  ExampleCatalog.register(TranscribeAssemblyAIExample.self, path: TranscribeAssemblyAIExample.name)
  ExampleCatalog.register(
    TranscribeAssemblyAIURLExample.self, path: TranscribeAssemblyAIURLExample.name)
  ExampleCatalog.register(
    TranscribeAssemblyAIStringExample.self, path: TranscribeAssemblyAIStringExample.name)
  // Embed
  ExampleCatalog.register(EmbedOpenAIExample.self, path: EmbedOpenAIExample.name)
  ExampleCatalog.register(EmbedManyOpenAIExample.self, path: EmbedManyOpenAIExample.name)

  // Generate Image
  ExampleCatalog.register(GenerateImageOpenAIExample.self, path: GenerateImageOpenAIExample.name)

  // Generate Speech
  ExampleCatalog.register(GenerateSpeechOpenAIExample.self, path: GenerateSpeechOpenAIExample.name)

  // Stream Text
  ExampleCatalog.register(StreamTextOpenAIExample.self, path: StreamTextOpenAIExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnStepFinishExample.self, path: StreamTextOpenAIOnStepFinishExample.name)
  ExampleCatalog.register(StreamTextOpenAIAbortExample.self, path: StreamTextOpenAIAbortExample.name)
  ExampleCatalog.register(StreamTextOpenAIGlobalProviderExample.self, path: StreamTextOpenAIGlobalProviderExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnChunkExample.self, path: StreamTextOpenAIOnChunkExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnFinishExample.self, path: StreamTextOpenAIOnFinishExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnFinishStepsExample.self, path: StreamTextOpenAIOnFinishStepsExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnFinishResponseMessagesExample.self, path: StreamTextOpenAIOnFinishResponseMessagesExample.name)
  ExampleCatalog.register(StreamTextOpenAIAudioExample.self, path: StreamTextOpenAIAudioExample.name)
  ExampleCatalog.register(StreamTextOpenAICachedPromptTokensExample.self, path: StreamTextOpenAICachedPromptTokensExample.name)
  ExampleCatalog.register(StreamTextOpenAIOnChunkToolCallStreamingExample.self, path: StreamTextOpenAIOnChunkToolCallStreamingExample.name)
  ExampleCatalog.register(StreamTextOpenAIToolOutputStreamExample.self, path: StreamTextOpenAIToolOutputStreamExample.name)
  ExampleCatalog.register(StreamTextOpenAIOutputObjectExample.self, path: StreamTextOpenAIOutputObjectExample.name)
  ExampleCatalog.register(StreamTextOpenAIPrepareStepExample.self, path: StreamTextOpenAIPrepareStepExample.name)
  ExampleCatalog.register(StreamTextOpenAIWebSearchToolExample.self, path: StreamTextOpenAIWebSearchToolExample.name)
  ExampleCatalog.register(StreamTextOpenAICodeInterpreterToolExample.self, path: StreamTextOpenAICodeInterpreterToolExample.name)
  ExampleCatalog.register(StreamTextOpenAIImageGenerationToolExample.self, path: StreamTextOpenAIImageGenerationToolExample.name)
  ExampleCatalog.register(StreamTextOpenAILocalShellToolExample.self, path: StreamTextOpenAILocalShellToolExample.name)
  ExampleCatalog.register(StreamTextOpenAIFullstreamLogprobsExample.self, path: StreamTextOpenAIFullstreamLogprobsExample.name)
  ExampleCatalog.register(StreamTextOpenAIToolApprovalExample.self, path: StreamTextOpenAIToolApprovalExample.name)
  ExampleCatalog.register(StreamTextOpenAIToolApprovalDynamicExample.self, path: StreamTextOpenAIToolApprovalDynamicExample.name)
  ExampleCatalog.register(StreamTextOpenAIReadUIMessageStreamExample.self, path: StreamTextOpenAIReadUIMessageStreamExample.name)
  ExampleCatalog.register(StreamTextOpenAIToolCallExample.self, path: StreamTextOpenAIToolCallExample.name)
  ExampleCatalog.register(StreamTextOpenAIToolCallRawJSONSchemaExample.self, path: StreamTextOpenAIToolCallRawJSONSchemaExample.name)
  ExampleCatalog.register(StreamTextOpenAIRequestBodyExample.self, path: StreamTextOpenAIRequestBodyExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesExample.self, path: StreamTextOpenAIResponsesExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesRawChunksExample.self, path: StreamTextOpenAIResponsesRawChunksExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesReasoningSummaryExample.self, path: StreamTextOpenAIResponsesReasoningSummaryExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesReasoningToolCallExample.self, path: StreamTextOpenAIResponsesReasoningToolCallExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesReasoningWebSearchExample.self, path: StreamTextOpenAIResponsesReasoningWebSearchExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesReasoningZeroDataRetentionExample.self, path: StreamTextOpenAIResponsesReasoningZeroDataRetentionExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesToolCallExample.self, path: StreamTextOpenAIResponsesToolCallExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesServiceTierExample.self, path: StreamTextOpenAIResponsesServiceTierExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesChatbotExample.self, path: StreamTextOpenAIResponsesChatbotExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesCodeInterpreterExample.self, path: StreamTextOpenAIResponsesCodeInterpreterExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesFileSearchExample.self, path: StreamTextOpenAIResponsesFileSearchExample.name)
  ExampleCatalog.register(StreamTextOpenAIResponsesMCPToolExample.self, path: StreamTextOpenAIResponsesMCPToolExample.name)

  // Agents
  ExampleCatalog.register(AgentOpenAIStreamExample.self, path: AgentOpenAIStreamExample.name)
  ExampleCatalog.register(AgentOpenAIStreamToolsExample.self, path: AgentOpenAIStreamToolsExample.name)
  ExampleCatalog.register(AgentOpenAIGenerateExample.self, path: AgentOpenAIGenerateExample.name)

  // Complex
  ExampleCatalog.register(SemanticRouterExample.self, path: SemanticRouterExample.name)
  ExampleCatalog.register(MathAgentExample.self, path: MathAgentExample.name)
  ExampleCatalog.register(MathAgentRequiredToolChoiceExample.self, path: MathAgentRequiredToolChoiceExample.name)

  // Agents
  ExampleCatalog.register(AgentOpenAIGenerateExample.self, path: AgentOpenAIGenerateExample.name)
  ExampleCatalog.register(AgentOpenAIStreamExample.self, path: AgentOpenAIStreamExample.name)
  ExampleCatalog.register(AgentOpenAIStreamToolsExample.self, path: AgentOpenAIStreamToolsExample.name)
  ExampleCatalog.register(AgentOpenAIGenerateJSONExample.self, path: AgentOpenAIGenerateJSONExample.name)
  ExampleCatalog.register(AgentOpenAIStreamJSONExample.self, path: AgentOpenAIStreamJSONExample.name)
  ExampleCatalog.register(AgentOpenAIGenerateOnFinishExample.self, path: AgentOpenAIGenerateOnFinishExample.name)
  ExampleCatalog.register(AgentOpenAIGenerateCallOptionsExample.self, path: AgentOpenAIGenerateCallOptionsExample.name)
  ExampleCatalog.register(AgentOpenAIStreamCallOptionsExample.self, path: AgentOpenAIStreamCallOptionsExample.name)

  // Registry
  ExampleCatalog.register(RegistryStreamTextOpenAIExample.self, path: RegistryStreamTextOpenAIExample.name)
  ExampleCatalog.register(RegistryEmbedOpenAIExample.self, path: RegistryEmbedOpenAIExample.name)
  ExampleCatalog.register(RegistryGenerateImageOpenAIExample.self, path: RegistryGenerateImageOpenAIExample.name)
  ExampleCatalog.register(RegistryGenerateSpeechOpenAIExample.self, path: RegistryGenerateSpeechOpenAIExample.name)
  ExampleCatalog.register(RegistryTranscribeOpenAIExample.self, path: RegistryTranscribeOpenAIExample.name)
}
