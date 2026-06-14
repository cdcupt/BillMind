import "./screen.css";

export function StatsScreen() {
  return (
    <section>
      <h1 className="screen__title">Stats</h1>
      <p className="screen__sub">Where the money went.</p>
      <div className="note-card">
        <p className="muted">
          Totals and the per-category breakdown render here from
          <code> GET /v1/stats</code> once sign-in is wired.
        </p>
      </div>
    </section>
  );
}
