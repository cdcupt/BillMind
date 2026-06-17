import "./screen.css";

export function MindsScreen() {
  return (
    <section>
      <h1 className="screen__title">Minds</h1>
      <p className="screen__sub">A hand-drawn timeline of the voyage.</p>
      <div className="note-card">
        <p className="muted">
          The generated timeline infographic appears here. Minds is iOS-first;
          the web view is read-only.
        </p>
      </div>
    </section>
  );
}
