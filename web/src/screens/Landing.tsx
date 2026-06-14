import "./landing.css";

/**
 * Voyage landing — the unauthenticated front door. The hero states the one
 * promise ("talk to record"), the three pillars echo the app's surfaces, and
 * the sign-in stamps slot in here once Google Identity Services is wired
 * (slice: web auth). For now they are presentational anchors.
 */
export function Landing() {
  return (
    <main className="landing">
      <header className="landing__nav">
        <span className="landing__mark">
          BillMind<span className="landing__mark-dot">.</span>
        </span>
        <span className="landing__passport">— a travel ledger</span>
      </header>

      <section className="landing__hero" aria-labelledby="hero-heading">
        <p className="landing__eyebrow">Your travel-and-money agent</p>
        <h1 id="hero-heading" className="landing__title">
          Talk to record.<br />
          Watch it add up.
        </h1>
        <p className="landing__lede">
          Snap a receipt or just say what you spent. BillMind reads it, asks
          only what it must, and never guesses the number.
        </p>

        <div className="landing__actions">
          <button className="stamp-button" type="button">
            Continue with Apple
          </button>
          <button className="stamp-button stamp-button--ghost" type="button">
            Continue with Google
          </button>
        </div>
        <p className="landing__fineprint">
          Sign-in arrives with the web-auth slice — the API and ledger are live.
        </p>
      </section>

      <section className="landing__pillars" aria-label="What it does">
        <article className="pillar">
          <span className="pillar__num">01</span>
          <h2 className="pillar__title">Record</h2>
          <p>Photo, voice, or a line of text — one calm card to confirm.</p>
        </article>
        <article className="pillar">
          <span className="pillar__num">02</span>
          <h2 className="pillar__title">Stats</h2>
          <p>Where the money went, by trip and by category, kept honest.</p>
        </article>
        <article className="pillar">
          <span className="pillar__num">03</span>
          <h2 className="pillar__title">Minds</h2>
          <p>A hand-drawn timeline of the voyage, made from your ledger.</p>
        </article>
      </section>

      <footer className="landing__foot">
        <span>BillMind 2.0</span>
        <span>Never guess money.</span>
      </footer>
    </main>
  );
}
