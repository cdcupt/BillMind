import { useEffect, useState } from "react";
import "./screen.css";
import { api, ApiError, type User } from "../api/client";
import { clearSession, getSession } from "../api/session";

export function SettingsScreen() {
  const [user, setUser] = useState<User | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    api
      .me()
      .then((u) => active && setUser(u))
      .catch((e: unknown) =>
        active && setError(e instanceof ApiError ? e.reason : "Failed to load"),
      );
    return () => {
      active = false;
    };
  }, []);

  async function signOut() {
    const session = getSession();
    if (session) {
      try {
        await api.logout(session.refreshToken);
      } catch {
        // best-effort; clear locally regardless
      }
    }
    clearSession();
  }

  return (
    <section>
      <h1 className="screen__title">Settings</h1>
      <p className="screen__sub">Your account.</p>

      <div className="note-card" style={{ marginBottom: "1rem" }}>
        {error && <p className="muted">{error}</p>}
        {!error && !user && <p className="muted">Loading…</p>}
        {user && (
          <dl style={{ margin: 0, display: "grid", gap: "0.5rem" }}>
            <div>
              <dt className="muted">Name</dt>
              <dd style={{ margin: 0 }}>{user.displayName ?? "—"}</dd>
            </div>
            <div>
              <dt className="muted">Email</dt>
              <dd style={{ margin: 0 }}>{user.email ?? "—"}</dd>
            </div>
            <div>
              <dt className="muted">Plan</dt>
              <dd style={{ margin: 0 }}>{user.aiQuotaTier}</dd>
            </div>
          </dl>
        )}
      </div>

      <button className="stamp-button" type="button" onClick={signOut}>
        Sign out
      </button>
    </section>
  );
}
