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
				{ label: "Introduction", link: "/intro" },
				{ label: "Getting Started", link: "/getting-started" },
				{
					label: "Swift AI SDK Core",
					items: [
						{ label: "Generate Text", link: "/core/generate-text" },
						{ label: "Stream Text", link: "/core/stream-text" },
						{ label: "Generate Object", link: "/core/generate-object" },
						{ label: "Tools", link: "/core/tools" }
					]
				},
				{ label: "Providers & Models", link: "/providers" },
				{ label: "Attribution", link: "/about/attribution" }
			],
		}),
	],
});
