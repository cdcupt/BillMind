import { useCallback, useEffect, useState } from "react";
import { api, ApiError, type Trip } from "../api/client";

interface TripsState {
  trips: Trip[];
  loading: boolean;
  error: string | null;
  reload: () => void;
}

/** Loads the signed-in user's trips, with an imperative reload for after a
 *  create. Errors surface as a string for the UI to render. */
export function useTrips(): TripsState {
  const [trips, setTrips] = useState<Trip[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    api
      .trips()
      .then((t) => {
        if (active) setTrips(t);
      })
      .catch((e: unknown) => {
        if (active) setError(e instanceof ApiError ? e.reason : "Failed to load trips");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [nonce]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);
  return { trips, loading, error, reload };
}
