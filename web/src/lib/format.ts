// Display helpers. Money crosses the wire as a decimal string (never a float);
// we format for display but keep the raw string for any value we send back.

export function formatMoney(amount: string | null | undefined, currencyCode: string): string {
  if (amount == null || amount === "") return "—";
  const n = Number(amount);
  if (!Number.isFinite(n)) return `${amount} ${currencyCode}`;
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currencyCode,
      maximumFractionDigits: 2,
    }).format(n);
  } catch {
    // Unknown currency code → plain number + code.
    return `${n.toLocaleString()} ${currencyCode}`;
  }
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

/** A human label for a category raw value (e.g. "accommodation" → "Accommodation"). */
export function titleCase(raw: string | null | undefined): string {
  if (!raw) return "—";
  return raw.charAt(0).toUpperCase() + raw.slice(1);
}
