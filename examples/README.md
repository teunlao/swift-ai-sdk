# Swift AI SDK Examples

Curated examples that mirror the structure of the upstream Vercel AI SDK. Each snippet is kept in sync with the TypeScript originals and exercises the same public surface area of the Swift port.

## Layout

```
examples/
├── Sources/
│   ├── ExamplesCore/          # Shared logging/env helpers + example registry
│   └── AICoreExamples/        # Swift ports of `external/vercel-ai-sdk/examples/ai-core/src`
│       ├── ExampleIndex.swift # Registers all available examples with the CLI
│       ├── Main.swift         # CLI entry point (list + run by path)
│       └── Tools/
│           └── WeatherTool.swift
└── Package.swift              # SwiftPM manifest (other legacy targets are being migrated here)
```

> We are consolidating the legacy per-target examples into the `AICoreExamples` executable so that the folder layout matches `examples/ai-core/src` upstream. New examples should live under `AICoreExamples/<category>/` with the same path as the TypeScript source.

## Environment

Copy the template and provide provider keys (only the variables you need for a given run are required):

```bash
cp .env.example .env
# edit .env and add OPENAI_API_KEY / ANTHROPIC_API_KEY / ...
```

The CLI automatically loads `.env` through `ExamplesCore.EnvLoader`.

## Running examples

List everything that is currently registered:

```bash
cd examples
swift run AICoreExamples --list
```

Run a specific example by its upstream-like path:

```bash
swift run AICoreExamples tools/weather-tool
```

Behind the scenes the CLI looks up the entry in `ExampleCatalog`, loads environment variables, runs the example, and prints structured logs plus JSON output.

### Building / testing

```bash
cd examples
swift build --target AICoreExamples          # build the consolidated executable
swift run AICoreExamples tools/weather-tool  # ad-hoc smoke run (also exercises OpenAI call if key set)
```

(Existing standalone targets remain in `Package.swift` while we migrate them. They keep compiling, but new work should use the CLI flow above.)

## Adding a new example

1. **Create a Swift file** that mirrors the upstream path, e.g. `Sources/AICoreExamples/GenerateText/Basic.swift`.
2. **Conform to `Example`** (or `CLIExample` if you need a dedicated `main`) and implement `run()` using the shared utilities.
3. **Register it** inside `registerAllExamples()` in `ExampleIndex.swift`:
   ```swift
   ExampleCatalog.register(GenerateTextBasic.self, path: GenerateTextBasic.name)
   ```
4. **Keep parity** with the corresponding TypeScript file under `external/vercel-ai-sdk/examples/ai-core/src`.
5. **Verify** via `swift run AICoreExamples <path>` and, if needed, add targeted validation under `ExamplesCore` tests.

By following these steps we maintain a one-to-one mapping between Swift and TypeScript examples, ensuring that documentation links, build automation, and manual validation stay aligned.
