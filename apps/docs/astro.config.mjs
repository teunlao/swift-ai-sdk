import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://swift-ai-sdk.dev",
 	integrations: [
		starlight({
			title: "Swift AI SDK",
      logo: {
        dark: "./src/assets/logo-light.png",
        light: "./src/assets/logo-dark.png",
        alt: "Swift AI SDK",
        replacesTitle: true,
      },
      favicon: "/favicon.ico",
      head: [
        {
          tag: "link",
          attrs: { rel: "apple-touch-icon", sizes: "180x180", href: "/apple-touch-icon.png" },
        },
      ],
			customCss: ['./src/styles/custom.css'],
    social: [
        { icon: "github", label: "GitHub", href: "https://github.com/teunlao/swift-ai-sdk" }
      ],
			sidebar: [
        {
          label: "Getting Started",
          items: [
            { label: "Navigating the Library", link: "/getting-started/navigating-the-library" },
            { label: "iOS & macOS", link: "/getting-started/ios-macos-quickstart" },
            { label: "Server (Vapor)", link: "/getting-started/server-vapor-quickstart" },
            { label: "CLI", link: "/getting-started/cli-quickstart" }
          ]
        },
        {
          label: "AI SDK Core",
          items: [
            { label: "Overview", link: "/ai-sdk-core/overview" },
            { label: "Generating & Streaming Text", link: "/ai-sdk-core/generating-text" },
            { label: "Generating Structured Data", link: "/ai-sdk-core/generating-structured-data" },
            { label: "Tools and Tool Calling", link: "/ai-sdk-core/tools-and-tool-calling" },
            { label: "Model Context Protocol (MCP) Tools", link: "/ai-sdk-core/mcp-tools" },
            { label: "Prompt Engineering", link: "/ai-sdk-core/prompt-engineering" },
            { label: "Settings", link: "/ai-sdk-core/settings" },
            { label: "Embeddings", link: "/ai-sdk-core/embeddings" },
            { label: "Image Generation", link: "/ai-sdk-core/image-generation" },
            { label: "Transcription", link: "/ai-sdk-core/transcription" },
            { label: "Speech", link: "/ai-sdk-core/speech" },
            { label: "Language Model Middleware", link: "/ai-sdk-core/middleware" },
            { label: "Provider & Model Management", link: "/ai-sdk-core/provider-management" },
            { label: "Error Handling", link: "/ai-sdk-core/error-handling" },
            { label: "Testing", link: "/ai-sdk-core/testing" },
            { label: "Telemetry", link: "/ai-sdk-core/telemetry" }
          ]
        },
        {
          label: "Zod Adapter",
          items: [
            { label: "Zod-like Schema DSL", link: "/zod-adapter/overview" }
          ]
        },
        {
          label: "Foundations",
          items: [
            { label: "Overview", link: "/foundations/overview" },
            { label: "Providers and Models", link: "/foundations/providers-and-models" },
            { label: "Prompts", link: "/foundations/prompts" },
            { label: "Tools", link: "/foundations/tools" },
            { label: "Streaming", link: "/foundations/streaming" }
          ]
        },
        {
          label: "Agents",
          items: [
            { label: "Overview", link: "/agents/overview" },
            { label: "Building Agents", link: "/agents/building-agents" },
            { label: "Workflow Patterns", link: "/agents/workflows" },
            { label: "Loop Control", link: "/agents/loop-control" }
          ]
        },
        {
          label: "Providers",
          items: [
            { label: "Overview", link: "/providers/overview" },
            { label: "OpenAI", link: "/providers/openai" },
            { label: "Anthropic", link: "/providers/anthropic" },
            { label: "Google Generative AI", link: "/providers/google-generative-ai" },
            { label: "Replicate", link: "/providers/replicate" },
            { label: "LMNT", link: "/providers/lmnt" }
          ]
        }
			],
		}),
	],
});
