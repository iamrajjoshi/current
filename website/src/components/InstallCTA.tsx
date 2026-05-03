export function InstallCTA() {
  return (
    <section className="install-section" id="install">
      <div className="shell install-inner">
        <div>
          <p className="eyebrow">Install</p>
          <h2>Install Current on macOS.</h2>
          <p>The release is packaged as an unsigned app through the Homebrew tap.</p>
        </div>
        <div className="install-actions">
          <pre className="command-panel"><code>brew install --cask iamrajjoshi/tap/current</code></pre>
          <a className="button primary" href="https://github.com/iamrajjoshi/current/releases" rel="noreferrer">
            Releases
          </a>
          <a className="button secondary" href="https://github.com/iamrajjoshi/current" rel="noreferrer">
            GitHub
          </a>
        </div>
      </div>
    </section>
  );
}
