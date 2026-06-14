import { useEffect, useState } from "react";
import { api, ApiError, type Bill } from "../api/client";
import { formatDate, formatMoney, titleCase } from "../lib/format";
import "./bills.css";

const CATEGORIES = [
  "food",
  "transport",
  "accommodation",
  "shopping",
  "entertainment",
  "utilities",
  "medical",
  "education",
  "subscription",
  "misc",
];

interface Props {
  tripID: string;
  currency: string;
  /** Bump to force a refetch (e.g. after a capture is saved). */
  refreshToken: number;
}

/** The trip's saved bills: a tappable list that opens a per-bill editor with
 *  edit + delete. Read+write against /v1/trips/:id/bills and /v1/bills/:id. */
export function BillsList({ tripID, currency, refreshToken }: Props) {
  const [bills, setBills] = useState<Bill[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Bill | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const reload = () => setReloadKey((k) => k + 1);

  // Abort-safe: if tripID changes mid-flight, the stale response is dropped
  // instead of clobbering the new trip's list.
  useEffect(() => {
    const ac = new AbortController();
    setLoading(true);
    setError(null);
    api
      .billsInTrip(tripID, ac.signal)
      .then(setBills)
      .catch((e) => {
        if (e instanceof DOMException && e.name === "AbortError") return;
        setError(e instanceof ApiError ? e.reason : "Couldn't load your bills.");
      })
      .finally(() => {
        if (!ac.signal.aborted) setLoading(false);
      });
    return () => ac.abort();
  }, [tripID, refreshToken, reloadKey]);

  const total = bills.reduce((sum, b) => sum + (Number(b.amount) || 0), 0);

  return (
    <section className="bills" aria-label="Saved bills">
      <header className="bills__head">
        <h2 className="bills__title">In this trip</h2>
        {!loading && bills.length > 0 && (
          <span className="bills__sum">
            {bills.length} {bills.length === 1 ? "bill" : "bills"} ·{" "}
            {formatMoney(String(total), currency)}
          </span>
        )}
      </header>

      {loading ? (
        <p className="muted bills__empty">Loading…</p>
      ) : error ? (
        <div className="note-card">
          <p className="muted">{error}</p>
          <button className="stamp-button stamp-button--ghost" type="button" onClick={reload}>
            Retry
          </button>
        </div>
      ) : bills.length === 0 ? (
        <p className="muted bills__empty">No bills yet — record one above and it lands here.</p>
      ) : (
        <ul className="bills__list">
          {bills.map((b) => (
            <li key={b.id}>
              <button type="button" className="bill-row" onClick={() => setEditing(b)}>
                <span className="bill-row__main">
                  <span className="bill-row__merchant">{b.merchant || titleCase(b.categoryRaw)}</span>
                  <span className="bill-row__meta">
                    {titleCase(b.categoryRaw)} · {formatDate(b.date)}
                  </span>
                </span>
                <span className="bill-row__amount">{formatMoney(b.amount, b.currencyCode)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {editing && (
        <BillEditor
          key={editing.id}
          bill={editing}
          onClose={() => setEditing(null)}
          onChanged={() => {
            setEditing(null);
            reload();
          }}
        />
      )}
    </section>
  );
}

function toDateInput(iso: string | null | undefined): string {
  if (!iso) return "";
  // Slice the date portion straight off the ISO string — never round-trip through
  // `new Date()`, which shifts the day for negative-offset timezones.
  const m = /^\d{4}-\d{2}-\d{2}/.exec(iso);
  return m ? m[0] : "";
}

interface EditorProps {
  bill: Bill;
  onClose: () => void;
  onChanged: () => void;
}

function BillEditor({ bill, onClose, onChanged }: EditorProps) {
  const [merchant, setMerchant] = useState(bill.merchant ?? "");
  const [amount, setAmount] = useState(bill.amount);
  const [categoryRaw, setCategoryRaw] = useState(bill.categoryRaw ?? "misc");
  const [date, setDate] = useState(toDateInput(bill.date));
  const [notes, setNotes] = useState(bill.notes ?? "");
  const [busy, setBusy] = useState<null | "save" | "delete">(null);
  const [error, setError] = useState<string | null>(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  // Escape closes the sheet (unless a request is in flight).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !busy) onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [busy, onClose]);

  const canSave = amount.trim() !== "" && Number(amount) > 0 && date !== "";

  async function save() {
    if (busy) return;
    setBusy("save");
    setError(null);
    try {
      await api.updateBill(bill.id, {
        merchant: merchant.trim() || null,
        amount: amount.trim(),
        currencyCode: bill.currencyCode,
        date: new Date(`${date}T12:00:00.000Z`).toISOString(),
        categoryRaw,
        notes: notes.trim() || null,
      });
      onChanged();
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Couldn't save the change.");
      setBusy(null);
    }
  }

  async function remove() {
    if (busy) return;
    setBusy("delete");
    setError(null);
    try {
      await api.deleteBill(bill.id);
      onChanged();
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Couldn't delete the bill.");
      setBusy(null);
    }
  }

  return (
    <div className="bill-modal" role="dialog" aria-modal="true" aria-label="Edit bill">
      <div className="bill-modal__scrim" onClick={busy ? undefined : onClose} />
      <div className="bill-modal__sheet">
        <header className="bill-modal__head">
          <h3>Edit bill</h3>
          <button className="bill-modal__close" type="button" onClick={onClose} aria-label="Close" disabled={!!busy}>
            ✕
          </button>
        </header>

        <label className="field">
          <span className="field__label">Merchant</span>
          <input className="field__input" value={merchant} placeholder="Where?" onChange={(e) => setMerchant(e.target.value)} />
        </label>

        <label className={`field${!canSave ? " field--needed" : ""}`}>
          <span className="field__label">
            Amount {amount.trim() !== "" && Number(amount) <= 0 && <em className="field__flag">must be positive</em>}
          </span>
          <div className="field__money">
            <span className="field__currency">{bill.currencyCode}</span>
            <input
              className="field__input"
              inputMode="decimal"
              value={amount}
              placeholder="0.00"
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
        </label>

        <fieldset className="field">
          <span className="field__label">Category</span>
          <div className="chips">
            {CATEGORIES.map((opt) => (
              <button
                key={opt}
                type="button"
                className={`chip${categoryRaw === opt ? " chip--on" : ""}`}
                onClick={() => setCategoryRaw(opt)}
              >
                {titleCase(opt)}
              </button>
            ))}
          </div>
        </fieldset>

        <label className="field">
          <span className="field__label">Date</span>
          <input type="date" className="field__input" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>

        <label className="field">
          <span className="field__label">Notes</span>
          <input className="field__input" value={notes} placeholder="Optional" onChange={(e) => setNotes(e.target.value)} />
        </label>

        {error && <p className="capture-card__error">{error}</p>}

        <div className="bill-modal__actions">
          {confirmingDelete ? (
            <>
              <span className="bill-modal__confirm">Delete this bill?</span>
              <button className="stamp-button stamp-button--ghost" type="button" onClick={() => setConfirmingDelete(false)} disabled={!!busy}>
                Keep
              </button>
              <button className="stamp-button stamp-button--danger" type="button" onClick={() => void remove()} disabled={!!busy}>
                {busy === "delete" ? "Deleting…" : "Delete"}
              </button>
            </>
          ) : (
            <>
              <button className="stamp-button stamp-button--danger-ghost" type="button" onClick={() => setConfirmingDelete(true)} disabled={!!busy}>
                Delete
              </button>
              <button className="stamp-button" type="button" onClick={() => void save()} disabled={!canSave || !!busy}>
                {busy === "save" ? "Saving…" : "Save changes"}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
