import { useEffect, useRef, useState } from "react";
import { GOOGLE_CLIENT_ID, renderGoogleButton } from "../auth/google";

interface Props {
  onCredential: (idToken: string) => void;
}

/** Renders the GIS button. When the client ID is not configured, renders a
 *  small note instead of a dead button. */
export function GoogleSignIn({ onCredential }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "unconfigured" | "error">(
    GOOGLE_CLIENT_ID ? "loading" : "unconfigured",
  );

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID || !ref.current) return;
    let active = true;
    renderGoogleButton(ref.current, onCredential)
      .then((rendered) => active && setStatus(rendered ? "ready" : "unconfigured"))
      .catch(() => active && setStatus("error"));
    return () => {
      active = false;
    };
  }, [onCredential]);

  if (status === "unconfigured") {
    return (
      <p className="landing__fineprint">
        Google sign-in isn’t configured for this build (set
        <code> VITE_GOOGLE_CLIENT_ID</code>).
      </p>
    );
  }
  if (status === "error") {
    return <p className="landing__fineprint">Couldn’t load Google sign-in.</p>;
  }
  return <div ref={ref} aria-label="Sign in with Google" />;
}
