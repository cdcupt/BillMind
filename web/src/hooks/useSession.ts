import { useEffect, useState } from "react";
import { getSession, onSessionChange, type Session } from "../api/session";

/** Re-renders the subscriber whenever the session is set or cleared. */
export function useSession(): Session | null {
  const [session, setSession] = useState<Session | null>(getSession);
  useEffect(() => onSessionChange(setSession), []);
  return session;
}
