import { useCallback, useState } from "react";
import { api, ApiError } from "../api/client";
import { setSession } from "../api/session";
import { GoogleSignIn } from "../components/GoogleSignIn";
import "./landing.css";

/**
 * Voyage landing — the unauthenticated front door. The hero states the one
 * promise ("talk to record"), the pillars echo the app's surfaces, and sign-in
 * exchanges a Google ID token for a session (setSession flips the app into the
 * authed shell). Web sign-in is Google-only by design; Apple sign-in lives in
 * the iOS app (native flow), not the web.
 */
export function Landing() {
  const [error, setError] = useState<string | null>(null);

  const handleGoogle = useCallback(async (idToken: string) => {
    setError(null);
    try {
      const tokens = await api.signIn("google", idToken);
      setSession({
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        userId: tokens.userID,
      });
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Sign-in failed — try again.");
    }
  }, []);

  return (
    <main className="landing">
      <header className="landing__nav">
        <span className="landing__mark">
          BillOwl<span className="landing__mark-dot">.</span>
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
          Snap a receipt or just say what you spent. BillOwl reads it, asks
          only what it must, and never guesses the number.
        </p>

        <div className="landing__actions">
          <GoogleSignIn onCredential={handleGoogle} />
        </div>
        {error && <p className="landing__error">{error}</p>}
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
        <span>BillOwl 2.0</span>
        <span>Never guess money.</span>
      </footer>
    </main>
  );
}
