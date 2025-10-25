import ExamplesCore

func registerAllExamples() {
  ExampleCatalog.register(WeatherToolExample.self, path: WeatherToolExample.name)
  ExampleCatalog.register(GenerateTextOpenAIExample.self, path: GenerateTextOpenAIExample.name)
  ExampleCatalog.register(GenerateTextOpenAIOutputObjectExample.self, path: GenerateTextOpenAIOutputObjectExample.name)
  ExampleCatalog.register(GenerateObjectOpenAIExample.self, path: GenerateObjectOpenAIExample.name)
}
