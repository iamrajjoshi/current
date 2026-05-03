const tree = `~/Documents/current/
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
          <p className="eyebrow">Storage</p>
          <h2>Your notes are just files.</h2>
          <p>
            By default, Current stores one Markdown file per day under `~/Documents/current`. Reveal the folder, back it up, sync it, or edit a file outside the app.
          </p>
          <div className="trust-list">
            <span>Default library: Documents</span>
            <span>External edit conflict checks</span>
          </div>
        </div>
        <pre className="code-panel tree-panel"><code>{tree}</code></pre>
      </div>
    </section>
  );
}
