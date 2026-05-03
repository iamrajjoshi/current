import Link from "next/link";

export function Footer() {
  return (
    <footer className="site-footer">
      <div className="shell footer-inner">
        <Link href="/" className="footer-brand">Current</Link>
        <p>Daily notes for macOS. Markdown files you can find.</p>
        <div>
          <Link href="/settings/">Settings</Link>
          <a href="https://github.com/iamrajjoshi/current" rel="noreferrer">GitHub</a>
        </div>
      </div>
    </footer>
  );
}
