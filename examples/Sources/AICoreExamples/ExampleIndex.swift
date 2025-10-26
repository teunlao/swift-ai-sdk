import ExamplesCore

func registerAllExamples() {
  ExampleCatalog.register(WeatherToolExample.self, path: WeatherToolExample.name)
  ExampleCatalog.register(GenerateTextOpenAIExample.self, path: GenerateTextOpenAIExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolChoiceExample.self, path: GenerateTextOpenAIToolChoiceExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolCallExample.self, path: GenerateTextOpenAIToolCallExample.name)
  ExampleCatalog.register(GenerateTextOpenAIActiveToolsExample.self, path: GenerateTextOpenAIActiveToolsExample.name)
  ExampleCatalog.register(GenerateTextOpenAIWarningExample.self, path: GenerateTextOpenAIWarningExample.name)
  ExampleCatalog.register(GenerateTextOpenAINullableToolExample.self, path: GenerateTextOpenAINullableToolExample.name)
  ExampleCatalog.register(GenerateTextOpenAITimeoutExample.self, path: GenerateTextOpenAITimeoutExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolApprovalExample.self, path: GenerateTextOpenAIToolApprovalExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolApprovalDynamicExample.self, path: GenerateTextOpenAIToolApprovalDynamicExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolCallRawJSONSchemaExample.self, path: GenerateTextOpenAIToolCallRawJSONSchemaExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolCallWithContextExample.self, path: GenerateTextOpenAIToolCallWithContextExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolExecutionErrorExample.self, path: GenerateTextOpenAIToolExecutionErrorExample.name)
  ExampleCatalog.register(GenerateTextOpenAIOutputObjectExample.self, path: GenerateTextOpenAIOutputObjectExample.name)
  ExampleCatalog.register(GenerateObjectOpenAIExample.self, path: GenerateObjectOpenAIExample.name)
}
