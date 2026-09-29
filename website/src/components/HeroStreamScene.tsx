import { Github } from "lucide-react";
import Link from "next/link";

export function HeroStreamScene() {
  return (
    <section className="landing-hero">
      <div className="shell hero-content">
        <div className="hero-copy">
          <h1>Daily notes for Mac.</h1>
          <p className="hero-detail">
            Write in today’s note, organize your work into streams, and scroll back through earlier days. Current saves your notes as local Markdown files.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#install">
              Install Current
            </a>
            <Link className="button secondary" href="/settings/">
              Settings
            </Link>
            <a className="icon-link" href="https://github.com/iamrajjoshi/current" rel="noreferrer" aria-label="View Current on GitHub">
              <Github size={18} aria-hidden="true" />
            </a>
          </div>
          <div className="install-chip" aria-label="Install command">
            <code>brew install --cask iamrajjoshi/tap/current</code>
          </div>
        </div>
        <aside className="hero-note" aria-label="Example daily note">
          <p className="note-date">Monday, September 28</p>
          <h2>Vendor review</h2>
          <p>Moved to Thursday. Sam is checking the contract changes before we send the questions over.</p>
          <ul>
            <li>Confirm where backups are stored</li>
            <li>Ask about the 30-day deletion window</li>
          </ul>
          <p>12:06, still waiting on the updated security report.</p>
        </aside>
      </div>
    </section>
  );
}
