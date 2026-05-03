const roadmap = [
  ["Search", "Find across older days without turning the stream into a results dashboard."],
  ["Calendar", "Jump to a date without keeping a permanent calendar panel on screen."],
  ["Review", "Bring unfinished tasks forward when you ask for them."],
  ["Imports", "Pull useful text in, then leave the Markdown file readable."]
];

export function RoadmapSection() {
  return (
    <section className="section roadmap-section">
      <div className="shell">
        <div className="section-heading left">
          <p className="eyebrow">Later</p>
          <h2>Future work has to earn the chrome.</h2>
        </div>
        <div className="roadmap-list">
          {roadmap.map(([title, description], index) => (
            <article className="roadmap-item" key={title}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              <h3>{title}</h3>
              <p>{description}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
