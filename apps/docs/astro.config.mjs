import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

export default defineConfig({
	integrations: [
		starlight({
			title: "Swift AI SDK",
			social: { github: "https://github.com/teunlao/swift-ai-sdk" },
			sidebar: [
				{ label: "Introduction", link: "/intro" },
				{ label: "Getting Started", link: "/getting-started" },
				{ label: "Swift AI SDK Core", link: "/core" },
				{ label: "Providers & Models", link: "/providers" },
			],
		}),
	],
});
