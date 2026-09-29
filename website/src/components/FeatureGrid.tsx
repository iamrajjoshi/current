const todayLines = [
  "08:47  Vendor review",
  "- vendor review moved to Thursday",
  "- ask Sam for the latest risk note",
  "",
  "## Review",
  "- [ ] read the contract diff",
  "- [ ] send the renewal decision"
];

const historyRows = [
  ["Sat, May 2", "Contract review", "Two tasks still open"],
  ["Fri, May 1", "Renewal call", "Revised terms requested"],
  ["Apr 20–30", "No notes", "Expand these dates"],
  ["Older notes", "Load as you scroll", "Or jump to a date"]
];

export function FeatureGrid() {
  return (
    <section className="section evidence-section" id="features">
      <div className="shell evidence-shell">
        <div className="evidence-intro">
          <h2>Daily notes, grouped by stream.</h2>
          <p>
            Keep work and personal notes in separate streams. Each stream remembers your place and saves changes automatically.
          </p>
        </div>

        <div className="evidence-stack">
          <article className="evidence-row evidence-row-large">
            <div>
              <h3>Start with today&apos;s note.</h3>
              <p>Write meeting notes, add tasks, or paste text into the current day.</p>
            </div>
            <div className="stream-excerpt" aria-label="Example daily Markdown note">
              <div className="day-divider compact">
                <strong>Today · Sun, May 3</strong>
                <i />
              </div>
              <div className="editor-lines compact-lines">
                {todayLines.map((row, index) => (
                  <p className={row.startsWith("##") ? "heading-line" : ""} key={`${row}-${index}`}>
                    {row || "\u00a0"}
                  </p>
                ))}
              </div>
            </div>
          </article>

          <article className="evidence-row">
            <div>
              <h3>One Markdown file per day.</h3>
              <p>Each stream has its own folder. Notes are stored by year and month.</p>
            </div>
            <pre className="inline-code-panel"><code>~/Documents/current/streams/daily/2026/05/2026-05-03.md</code></pre>
          </article>

          <article className="evidence-row">
            <div>
              <h3>Find earlier notes.</h3>
              <p>Scroll through a stream, choose a date from the calendar, or search across your notes.</p>
            </div>
            <div className="history-list" aria-label="Current history behavior">
              {historyRows.map(([day, detail, note]) => (
                <div className="history-row" key={day}>
                  <span>{day}</span>
                  <strong>{detail}</strong>
                  <em>{note}</em>
                </div>
              ))}
            </div>
          </article>
        </div>
      </div>
    </section>
  );
}
