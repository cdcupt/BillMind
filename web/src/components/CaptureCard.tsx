import { useState } from "react";
import { api, ApiError, type Card } from "../api/client";
import { titleCase } from "../lib/format";
import "./capture-card.css";

interface EditableDraft {
  merchant: string;
  amount: string; // decimal string; "" = unknown
  currencyCode: string;
  categoryRaw: string;
  date: string; // yyyy-MM-dd for the input; "" = unknown
  source: string;
}

function toDateInput(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "" : d.toISOString().slice(0, 10);
}

function initDraft(card: Card): EditableDraft {
  const d = card.draft;
  return {
    merchant: d.merchant ?? "",
    amount: d.amount ?? "",
    currencyCode: d.currencyCode,
    categoryRaw: d.categoryRaw ?? "",
    date: toDateInput(d.date),
    source: d.source,
  };
}

interface Props {
  card: Card;
  /** Called with the saved bill id after a successful confirm. */
  onSaved: () => void;
}

/** The capture card: shows the recognized draft, lets the user resolve the
 *  gaps the server flagged (chips for options, inputs otherwise), and confirms.
 *  Amount is the hard gate — Save stays disabled until it is present, mirroring
 *  the server's 422 (money is never guessed). */
export function CaptureCard({ card, onSaved }: Props) {
  const [draft, setDraft] = useState<EditableDraft>(() => initDraft(card));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof EditableDraft>(key: K, value: EditableDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  const canSave = draft.amount.trim() !== "" && Number.isFinite(Number(draft.amount));

  async function save() {
    setSaving(true);
    setError(null);
    try {
      await api.confirm({
        tripID: card.tripID,
        merchant: draft.merchant || null,
        amount: draft.amount || null,
        currencyCode: draft.currencyCode || null,
        date: draft.date ? new Date(draft.date).toISOString() : null,
        categoryRaw: draft.categoryRaw || null,
        source: draft.source || null,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? e.reason : "Couldn't save — try again.");
    } finally {
      setSaving(false);
    }
  }

  // Gap option chips, keyed by the field they fill.
  const optionsFor = (field: string): string[] =>
    card.gaps.find((g) => g.field === field)?.options ?? [];

  return (
    <div className="capture-card">
      <div className="capture-card__tape" aria-hidden="true" />
      <h2 className="capture-card__title">Does this look right?</h2>

      <label className="field">
        <span className="field__label">Merchant</span>
        <input
          className="field__input"
          value={draft.merchant}
          placeholder="Where?"
          onChange={(e) => set("merchant", e.target.value)}
        />
      </label>

      <label className={`field${!canSave ? " field--needed" : ""}`}>
        <span className="field__label">
          Amount {!canSave && <em className="field__flag">needs a number</em>}
        </span>
        <div className="field__money">
          <span className="field__currency">{draft.currencyCode}</span>
          <input
            className="field__input"
            inputMode="decimal"
            value={draft.amount}
            placeholder="0.00"
            onChange={(e) => set("amount", e.target.value)}
          />
        </div>
      </label>

      <fieldset className="field">
        <span className="field__label">Category</span>
        <div className="chips">
          {(optionsFor("category").length
            ? optionsFor("category")
            : ["food", "transport", "accommodation", "shopping", "misc"]
          ).map((opt) => (
            <button
              key={opt}
              type="button"
              className={`chip${draft.categoryRaw === opt ? " chip--on" : ""}`}
              onClick={() => set("categoryRaw", opt)}
            >
              {titleCase(opt)}
            </button>
          ))}
        </div>
      </fieldset>

      <label className="field">
        <span className="field__label">Date</span>
        <input
          type="date"
          className="field__input"
          value={draft.date}
          onChange={(e) => set("date", e.target.value)}
        />
      </label>

      {error && <p className="capture-card__error">{error}</p>}

      <button
        type="button"
        className="stamp-button capture-card__save"
        disabled={!canSave || saving}
        onClick={save}
      >
        {saving ? "Saving…" : "Save to ledger"}
      </button>
    </div>
  );
}
