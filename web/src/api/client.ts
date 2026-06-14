// Typed API client. A thin fetch wrapper that attaches the bearer token,
// transparently refreshes it once on a 401, surfaces the server's error
// envelope, and returns typed bodies generated from contract/openapi.yaml.

import type { components } from "./schema";
import {
  clearSession,
  getSession,
  setSession,
  type Session,
} from "./session";

type Schemas = components["schemas"];

// Convenient aliases for the rest of the app.
export type AuthTokens = Schemas["AuthTokens"];
export type User = Schemas["User"];
export type Trip = Schemas["Trip"];
export type Bill = Schemas["Bill"];
export type Stats = Schemas["Stats"];
export type Card = Schemas["Card"];
export type CaptureResponse = Schemas["CaptureResponse"];
export type CaptureRequest = Schemas["CaptureRequest"];
export type ConfirmRequest = Schemas["ConfirmRequest"];
export type AgentTurn = Schemas["AgentTurn"];
export type Gap = Schemas["Gap"];

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly reason: string,
  ) {
    super(reason);
    this.name = "ApiError";
  }
}

interface RequestOptions {
  method?: string;
  body?: unknown;
  auth?: boolean;
  signal?: AbortSignal;
}

let refreshInFlight: Promise<Session | null> | null = null;

async function refreshSession(): Promise<Session | null> {
  const current = getSession();
  if (!current) return null;
  // De-dupe concurrent refreshes — the refresh token is single-use.
  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const res = await fetch("/v1/auth/refresh", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ refreshToken: current.refreshToken }),
        });
        if (!res.ok) {
          clearSession();
          return null;
        }
        const tokens = (await res.json()) as AuthTokens;
        const next: Session = {
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          userId: tokens.userID,
        };
        setSession(next);
        return next;
      } catch {
        clearSession();
        return null;
      } finally {
        refreshInFlight = null;
      }
    })();
  }
  return refreshInFlight;
}

export async function request<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const { method = "GET", body, auth = true, signal } = options;

  const send = async (token: string | null): Promise<Response> => {
    const headers: Record<string, string> = {};
    if (body !== undefined) headers["content-type"] = "application/json";
    if (auth && token) headers.authorization = `Bearer ${token}`;
    return fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
  };

  let token = auth ? (getSession()?.accessToken ?? null) : null;
  let res = await send(token);

  if (res.status === 401 && auth) {
    const refreshed = await refreshSession();
    if (refreshed) {
      token = refreshed.accessToken;
      res = await send(token);
    }
  }

  if (res.status === 204) return undefined as T;

  const text = await res.text();
  const parsed = text ? safeJson(text) : null;

  if (!res.ok) {
    const reason =
      (parsed && typeof parsed === "object" && "reason" in parsed
        ? String((parsed as { reason: unknown }).reason)
        : null) ?? `Request failed (${res.status})`;
    throw new ApiError(res.status, reason);
  }
  return parsed as T;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// ── Endpoint helpers ────────────────────────────────────────────────────────

export const api = {
  signIn: (provider: "apple" | "google", idToken: string, nonce?: string) =>
    request<AuthTokens>(`/v1/auth/${provider}`, {
      method: "POST",
      auth: false,
      body: { idToken, nonce },
    }),

  logout: (refreshToken: string) =>
    request<void>("/v1/auth/logout", {
      method: "POST",
      auth: false,
      body: { refreshToken },
    }),

  me: () => request<User>("/v1/account/me"),

  trips: () => request<Trip[]>("/v1/trips"),

  createTrip: (name: string, currencyCode: string, mascot?: string) =>
    request<Trip>("/v1/trips", {
      method: "POST",
      body: { name, currencyCode, mascot },
    }),

  billsInTrip: (tripID: string, signal?: AbortSignal) =>
    request<Bill[]>(`/v1/trips/${tripID}/bills`, { signal }),

  updateBill: (
    id: string,
    patch: {
      merchant: string | null;
      amount: string; // decimal string
      currencyCode: string;
      date: string; // ISO8601
      categoryRaw: string;
      notes: string | null;
    },
  ) => request<Bill>(`/v1/bills/${id}`, { method: "PATCH", body: patch }),

  deleteBill: (id: string) =>
    request<void>(`/v1/bills/${id}`, { method: "DELETE" }),

  recognize: (req: CaptureRequest) =>
    request<CaptureResponse>("/v1/recognition", { method: "POST", body: req }),

  confirm: (req: ConfirmRequest) =>
    request<Bill>("/v1/bills/confirm", { method: "POST", body: req }),

  stats: (params?: { tripId?: string; scope?: "trip" | "all" }) => {
    const q = new URLSearchParams();
    if (params?.tripId) q.set("tripId", params.tripId);
    if (params?.scope) q.set("scope", params.scope);
    const qs = q.toString();
    return request<Stats>(`/v1/stats${qs ? `?${qs}` : ""}`);
  },

  chat: (message: string) =>
    request<AgentTurn>("/v1/agent/chat", { method: "POST", body: { message } }),
};
