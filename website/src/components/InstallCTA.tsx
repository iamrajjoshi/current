export function InstallCTA() {
  return (
    <section className="install-section" id="install">
      <div className="shell install-inner">
        <div>
          <h2>Install Current on macOS.</h2>
          <p>Install with Homebrew or download the app from GitHub Releases. Current requires macOS 14 or later; releases are unsigned.</p>
        </div>
        <div className="install-actions">
          <pre className="command-panel"><code>brew install --cask iamrajjoshi/tap/current</code></pre>
          <a className="button primary" href="https://github.com/iamrajjoshi/current/releases" rel="noreferrer">
            Download
          </a>
          <a className="button secondary" href="https://github.com/iamrajjoshi/current" rel="noreferrer">
            GitHub
          </a>
        </div>
      </div>
    </section>
  );
}
