import ExamplesCore

func registerAllExamples() {
  ExampleCatalog.register(WeatherToolExample.self, path: WeatherToolExample.name)
  ExampleCatalog.register(GenerateTextOpenAIExample.self, path: GenerateTextOpenAIExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolChoiceExample.self, path: GenerateTextOpenAIToolChoiceExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolCallExample.self, path: GenerateTextOpenAIToolCallExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolCallWithContextExample.self, path: GenerateTextOpenAIToolCallWithContextExample.name)
  ExampleCatalog.register(GenerateTextOpenAIToolExecutionErrorExample.self, path: GenerateTextOpenAIToolExecutionErrorExample.name)
  ExampleCatalog.register(GenerateTextOpenAIOutputObjectExample.self, path: GenerateTextOpenAIOutputObjectExample.name)
  ExampleCatalog.register(GenerateObjectOpenAIExample.self, path: GenerateObjectOpenAIExample.name)
}
