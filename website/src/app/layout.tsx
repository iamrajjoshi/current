import type { Metadata } from "next";
import "./globals.css";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export const metadata: Metadata = {
  title: "Current - Daily notes for macOS",
  description:
    "Current is a native macOS app for one note per day, saved as Markdown files you can find on disk.",
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
