import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/app/**/*.{ts,tsx}",
    "./src/components/**/*.{ts,tsx}",
    "./src/lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "rgb(8, 10, 16)",
        muted: "rgb(15, 18, 27)",
        primary: {
          DEFAULT: "rgb(84, 113, 255)",
          foreground: "#ffffff",
        },
        success: "rgb(34, 197, 94)",
        warning: "rgb(234, 179, 8)",
        danger: "rgb(239, 68, 68)",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "-apple-system", "sans-serif"],
        mono: ["JetBrains Mono", "monospace"],
      },
    },
  },
  plugins: [],
};

export default config;
