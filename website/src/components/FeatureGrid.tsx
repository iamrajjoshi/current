const todayLines = [
  "08:47  Dropped in before inbox",
  "- vendor review moved to Thursday",
  "- ask Sam for the latest risk note",
  "",
  "## Review",
  "- [ ] read the contract diff",
  "- [ ] write down the decision, not the whole meeting"
];

const historyRows = [
  ["Sat, May 2", "3 lines", "collapsed"],
  ["Fri, May 1", "18 lines", "open"],
  ["Thu, Apr 30", "empty", "hidden weekend off"],
  ["Older notes", "loads as you scroll", "no button"]
];

export function FeatureGrid() {
  return (
    <section className="section evidence-section" id="features">
      <div className="shell evidence-shell">
        <div className="evidence-intro">
          <p className="eyebrow">How it works</p>
          <h2>One note per day, always ready.</h2>
          <p>
            You write in one timeline. Current creates the dated sections, autosaves changes, and lets older days stay nearby without turning your notes into a dashboard.
          </p>
        </div>

        <div className="evidence-stack">
          <article className="evidence-row evidence-row-large">
            <div>
              <p className="row-kicker">Open to today</p>
              <h3>The first thing you see is the note for this date.</h3>
            </div>
            <div className="stream-excerpt" aria-label="Example Current daily stream">
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
              <p className="row-kicker">Saved as Markdown</p>
              <h3>Each date has its own `.md` file on disk.</h3>
            </div>
            <pre className="inline-code-panel"><code>~/Documents/current/streams/daily/2026/05/2026-05-03.md</code></pre>
          </article>

          <article className="evidence-row">
            <div>
              <p className="row-kicker">Scroll back in time</p>
              <h3>Recent days are close by. Older days load as you scroll.</h3>
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

        <div className="refusal-strip" aria-label="Current does not include common workspace clutter">
          <span>account</span>
          <span>workspace setup</span>
          <span>proprietary note database</span>
          <span>dashboard before the text</span>
        </div>
      </div>
    </section>
  );
}
