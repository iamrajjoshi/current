import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/**/*.{ts,tsx,mdx}"
  ],
  theme: {
    extend: {
      colors: {
        "current-paper": "#ffffff",
        "current-paper-warm": "#f6f5f4",
        "current-ink": "rgba(0, 0, 0, 0.92)",
        "current-muted": "#615d59",
        "current-faint": "#a39e98",
        "current-line": "rgba(0, 0, 0, 0.10)",
        "current-soft-line": "rgba(0, 0, 0, 0.06)",
        "current-blue": "#0075de",
        "current-blue-soft": "#f2f9ff",
        "current-sage": "#55756b",
        "current-persimmon": "#b0643b"
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "Inter",
          "Segoe UI",
          "sans-serif"
        ],
        mono: [
          "SFMono-Regular",
          "ui-monospace",
          "Menlo",
          "Monaco",
          "Consolas",
          "monospace"
        ]
      }
    }
  },
  plugins: []
};

export default config;
