import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://swift-ai-sdk.dev",
	integrations: [
		starlight({
			title: "Swift AI SDK",
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
          label: "Agents",
          items: [
            { label: "Overview", link: "/agents/overview" },
            { label: "Building Agents", link: "/agents/building-agents" }
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
        }
			],
		}),
	],
});
