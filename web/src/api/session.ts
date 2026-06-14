// Session token storage. The access token is short-lived; the refresh token
// rotates on every use (the server revokes the presented one). We persist both
// so a reload keeps the session, and expose a tiny pub/sub so the UI re-renders
// on sign-in / sign-out.

const ACCESS_KEY = "billmind.access";
const REFRESH_KEY = "billmind.refresh";
const USER_KEY = "billmind.userId";

export interface Session {
  accessToken: string;
  refreshToken: string;
  userId: string;
}

type Listener = (session: Session | null) => void;
const listeners = new Set<Listener>();

export function getSession(): Session | null {
  const accessToken = localStorage.getItem(ACCESS_KEY);
  const refreshToken = localStorage.getItem(REFRESH_KEY);
  const userId = localStorage.getItem(USER_KEY);
  if (!accessToken || !refreshToken || !userId) return null;
  return { accessToken, refreshToken, userId };
}

export function setSession(session: Session): void {
  localStorage.setItem(ACCESS_KEY, session.accessToken);
  localStorage.setItem(REFRESH_KEY, session.refreshToken);
  localStorage.setItem(USER_KEY, session.userId);
  emit(session);
}

export function clearSession(): void {
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
  localStorage.removeItem(USER_KEY);
  emit(null);
}

export function onSessionChange(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function emit(session: Session | null): void {
  for (const listener of listeners) listener(session);
}
