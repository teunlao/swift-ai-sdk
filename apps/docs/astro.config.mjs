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
          label: "Foundations",
          items: [
            { label: "Overview", link: "/foundations/overview" }
          ]
        }
			],
		}),
	],
});
