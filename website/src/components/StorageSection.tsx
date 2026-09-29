const tree = `~/Documents/current/
├── .current-library.json
└── streams/
    └── daily/
        ├── .current-stream.json
        └── 2026/
            └── 05/
                └── 2026-05-03.md`;

export function StorageSection() {
  return (
    <section className="section storage-section" id="storage">
      <div className="shell storage-grid">
        <div>
          <h2>Markdown files on your Mac.</h2>
          <p>
            Current saves notes under <code>~/Documents/current</code> by default. Open the folder to back up your library or edit a note in another app.
          </p>
          <div className="trust-list">
            <span>Choose a different folder in settings.</span>
            <span>Review conflicts when a file changes outside Current.</span>
          </div>
        </div>
        <pre className="code-panel tree-panel"><code>{tree}</code></pre>
      </div>
    </section>
  );
}
