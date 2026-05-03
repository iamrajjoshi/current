import { ArrowRight, Github, Settings } from "lucide-react";
import Link from "next/link";
import { basePath } from "@/lib/base-path";

const rows = [
  "08:47  Dropped in before inbox",
  "- vendor review moved to Thursday",
  "- ask Sam for the latest risk note",
  "",
  "## Review",
  "- [ ] read the contract diff",
  "- [ ] write down the decision, not the whole meeting",
  "",
  "12:06  Paste the rough notes here. Clean later."
];

export function HeroStreamScene() {
  return (
    <section className="landing-hero">
      <div className="hero-paper" aria-hidden="true">
        <div className="stream-window">
          <div className="stream-body">
            <div className="day-divider">
              <strong>Today · Sun, May 3</strong>
              <i />
            </div>
            <div className="editor-lines">
              {rows.map((row, index) => (
                <p className={row.startsWith("##") ? "heading-line" : ""} key={`${row}-${index}`}>
                  {row || "\u00a0"}
                </p>
              ))}
            </div>
            <div className="day-divider muted">
              <strong>Tue, Apr 28</strong>
              <i />
            </div>
          </div>
        </div>
      </div>

      <div className="shell hero-content">
        <div className="hero-copy">
          <img className="hero-icon" src={`${basePath}/current-icon.png`} alt="" width={64} height={64} />
          <p className="eyebrow">Daily notes for macOS</p>
          <h1>Current</h1>
          <p className="hero-lines">
            A simple Mac app for the note you keep open all day.
          </p>
          <p className="hero-detail">
            Current opens to today, keeps past days close, and saves each day as a Markdown file in your Documents folder.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#install">
              <ArrowRight size={17} aria-hidden="true" />
              Install
            </a>
            <Link className="button secondary" href="/settings/">
              <Settings size={17} aria-hidden="true" />
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
      </div>
    </section>
  );
}
