import { useEffect, useRef, useState } from "react";
import { api, ApiError, type CaptureResponse } from "../api/client";
import { useTrips } from "../hooks/useTrips";
import { CaptureCard } from "../components/CaptureCard";
import "./screen.css";
import "./record.css";

type Phase =
  | { kind: "idle" }
  | { kind: "recognizing" }
  | { kind: "result"; response: CaptureResponse }
  | { kind: "saved" };

async function fileToBase64(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

export function RecordScreen() {
  const { trips, loading, error: tripsError, reload } = useTrips();
  const [tripID, setTripID] = useState<string>("");
  const [text, setText] = useState("");
  const [phase, setPhase] = useState<Phase>({ kind: "idle" });
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  // Default the trip selection once trips arrive.
  useEffect(() => {
    if (!tripID && trips.length) setTripID(trips[0].id);
  }, [trips, tripID]);

  async function recognize(payload: { text?: string; imageBase64?: string; mimeType?: string }) {
    if (!tripID) return;
    setError(null);
    setPhase({ kind: "recognizing" });
    try {
      const response = await api.recognize({ tripID, ...payload });
      setPhase({ kind: "result", response });
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Recognition failed — try again.");
      setPhase({ kind: "idle" });
    }
  }

  async function onText(e: React.FormEvent) {
    e.preventDefault();
    if (!text.trim()) return;
    await recognize({ text: text.trim() });
  }

  async function onPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const imageBase64 = await fileToBase64(file);
    await recognize({ imageBase64, mimeType: file.type || "image/jpeg" });
    if (fileRef.current) fileRef.current.value = "";
  }

  function reset() {
    setText("");
    setPhase({ kind: "idle" });
  }

  if (loading) {
    return (
      <section>
        <h1 className="screen__title">Record</h1>
        <p className="muted">Loading your trips…</p>
      </section>
    );
  }

  if (tripsError) {
    return (
      <section>
        <h1 className="screen__title">Record</h1>
        <div className="note-card">
          <p className="muted">{tripsError}</p>
          <button className="stamp-button stamp-button--ghost" type="button" onClick={reload}>
            Retry
          </button>
        </div>
      </section>
    );
  }

  if (!trips.length) {
    return <NoTrips onCreated={reload} />;
  }

  const result = phase.kind === "result" ? phase.response : null;

  return (
    <section className="record">
      <h1 className="screen__title">Record</h1>
      <p className="screen__sub">Tell me what you spent, or drop a receipt.</p>

      <div className="record__trip">
        <label htmlFor="trip" className="muted">
          Trip
        </label>
        <select
          id="trip"
          className="record__select"
          value={tripID}
          onChange={(e) => setTripID(e.target.value)}
        >
          {trips.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name} · {t.currencyCode}
            </option>
          ))}
        </select>
      </div>

      <form className="record__compose" onSubmit={onText}>
        <textarea
          className="record__text"
          rows={2}
          placeholder="e.g. ramen 2840, taxi to hotel 1200…"
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
        <div className="record__actions">
          <button
            className="stamp-button"
            type="submit"
            disabled={phase.kind === "recognizing" || !text.trim()}
          >
            {phase.kind === "recognizing" ? "Reading…" : "Record"}
          </button>
          <button
            type="button"
            className="stamp-button stamp-button--ghost"
            onClick={() => fileRef.current?.click()}
            disabled={phase.kind === "recognizing"}
          >
            📷 Receipt
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            hidden
            onChange={onPhoto}
          />
        </div>
      </form>

      {error && <p className="record__error">{error}</p>}

      {result?.declined && (
        <div className="note-card record__declined">
          <p>{result.message ?? "I can't help with that one."}</p>
        </div>
      )}

      {result?.card && (
        <CaptureCard
          card={result.card}
          onSaved={() => {
            setPhase({ kind: "saved" });
            setText("");
          }}
        />
      )}

      {phase.kind === "saved" && (
        <div className="note-card record__saved">
          <p>Saved to your ledger. ✶</p>
          <button className="stamp-button stamp-button--ghost" type="button" onClick={reset}>
            Record another
          </button>
        </div>
      )}
    </section>
  );
}

function NoTrips({ onCreated }: { onCreated: () => void }) {
  const [name, setName] = useState("");
  const [currency, setCurrency] = useState("JPY");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await api.createTrip(name.trim(), currency.trim() || "JPY");
      onCreated();
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Couldn't create the trip.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h1 className="screen__title">Start a voyage</h1>
      <p className="screen__sub">Create a trip to record against.</p>
      <form className="note-card record__new-trip" onSubmit={create}>
        <label className="field">
          <span className="field__label">Trip name</span>
          <input
            className="field__input"
            value={name}
            placeholder="Osaka, spring"
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <label className="field">
          <span className="field__label">Currency</span>
          <input
            className="field__input"
            value={currency}
            onChange={(e) => setCurrency(e.target.value.toUpperCase())}
          />
        </label>
        {error && <p className="record__error">{error}</p>}
        <button className="stamp-button" type="submit" disabled={busy || !name.trim()}>
          {busy ? "Creating…" : "Create trip"}
        </button>
      </form>
    </section>
  );
}
