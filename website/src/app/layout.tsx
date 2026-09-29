import type { Metadata } from "next";
import "./globals.css";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export const metadata: Metadata = {
  title: "Current - Daily notes for macOS",
  description:
    "Keep daily notes in separate streams, find earlier writing by date or search, and save your notes as local Markdown files on macOS.",
  icons: {
    icon: `${basePath}/current-icon.png`
  }
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
