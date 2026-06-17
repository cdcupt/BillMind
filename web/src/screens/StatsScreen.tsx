import { useEffect, useState } from "react";
import { api, ApiError, type Stats } from "../api/client";
import { useTrips } from "../hooks/useTrips";
import { formatMoney, titleCase } from "../lib/format";
import "./screen.css";
import "./stats.css";

const ALL = "__all__";

export function StatsScreen() {
  const { trips } = useTrips();
  const [scope, setScope] = useState<string>(ALL);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    const params = scope === ALL ? { scope: "all" as const } : { tripId: scope, scope: "trip" as const };
    api
      .stats(params)
      .then((s) => active && setStats(s))
      .catch((e: unknown) =>
        active && setError(e instanceof ApiError ? e.reason : "Failed to load stats"),
      )
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, [scope]);

  // Currency for display: the selected trip's, else the first trip's, else USD.
  const currency =
    trips.find((t) => t.id === scope)?.currencyCode ?? trips[0]?.currencyCode ?? "USD";

  const max =
    stats?.byCategory.reduce((m, c) => Math.max(m, Number(c.amount) || 0), 0) ?? 0;

  return (
    <section className="stats">
      <h1 className="screen__title">Stats</h1>
      <p className="screen__sub">Where the money went.</p>

      <div className="stats__scope">
        <button
          type="button"
          className={`chip${scope === ALL ? " chip--on" : ""}`}
          onClick={() => setScope(ALL)}
        >
          All trips
        </button>
        {trips.map((t) => (
          <button
            key={t.id}
            type="button"
            className={`chip${scope === t.id ? " chip--on" : ""}`}
            onClick={() => setScope(t.id)}
          >
            {t.name}
          </button>
        ))}
      </div>

      {loading && <p className="muted">Counting…</p>}
      {error && <p className="record__error">{error}</p>}

      {stats && !loading && (
        <>
          <div className="stats__headline note-card">
            <div>
              <span className="stats__total">{formatMoney(stats.total, currency)}</span>
              <span className="stats__total-label">total spent</span>
            </div>
            <div className="stats__count">
              <span className="stats__count-num">{stats.billCount}</span>
              <span className="stats__total-label">
                {stats.billCount === 1 ? "bill" : "bills"}
              </span>
            </div>
          </div>

          {stats.byCategory.length === 0 ? (
            <p className="muted">No bills yet — record one and it shows up here.</p>
          ) : (
            <ul className="stats__bars">
              {stats.byCategory
                .slice()
                .sort((a, b) => Number(b.amount) - Number(a.amount))
                .map((c) => {
                  const pct = max > 0 ? (Number(c.amount) / max) * 100 : 0;
                  return (
                    <li key={c.category} className="bar">
                      <div className="bar__head">
                        <span className="bar__name">{titleCase(c.category)}</span>
                        <span className="bar__value">{formatMoney(c.amount, currency)}</span>
                      </div>
                      <div className="bar__track">
                        <div className="bar__fill" style={{ width: `${pct}%` }} />
                      </div>
                    </li>
                  );
                })}
            </ul>
          )}
        </>
      )}
    </section>
  );
}
