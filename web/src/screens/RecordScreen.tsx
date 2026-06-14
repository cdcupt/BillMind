import "./screen.css";

/** Record home — the chat-first capture surface. Full capture flow (trip
 *  picker → text/photo → card → confirm) lands in the web-record slice; this
 *  is the placeholder that ships with the scaffold. */
export function RecordScreen() {
  return (
    <section>
      <h1 className="screen__title">Record</h1>
      <p className="screen__sub">Tell me what you spent, or drop a receipt.</p>
      <div className="note-card">
        <p className="muted">
          The capture flow (trip → recognize → confirm) is wired to the live API
          in the next slice. The contract and server endpoints it calls are
          already green.
        </p>
      </div>
    </section>
  );
}
