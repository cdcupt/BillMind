// Google Identity Services integration. We use the ID-token flow: GIS renders
// a branded button, and on success hands us a short-lived ID token (JWT) that
// we exchange server-side at /v1/auth/google. The client ID is build-time
// config (VITE_GOOGLE_CLIENT_ID); when it is absent, sign-in is "not
// configured" and the UI says so rather than rendering a dead button.

export const GOOGLE_CLIENT_ID: string | undefined =
  import.meta.env.VITE_GOOGLE_CLIENT_ID;

const GSI_SRC = "https://accounts.google.com/gsi/client";

let scriptPromise: Promise<void> | null = null;

/** Loads the GIS client script once (idempotent). */
export function loadGoogleScript(): Promise<void> {
  if (window.google?.accounts?.id) return Promise.resolve();
  if (scriptPromise) return scriptPromise;
  scriptPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = GSI_SRC;
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = () => {
      scriptPromise = null;
      reject(new Error("Failed to load Google sign-in"));
    };
    document.head.appendChild(script);
  });
  return scriptPromise;
}

/**
 * Loads GIS, initializes it with the client ID, and renders the button into
 * `parent`. Returns true when rendered, false when sign-in is not configured.
 */
export async function renderGoogleButton(
  parent: HTMLElement,
  onCredential: (idToken: string) => void,
): Promise<boolean> {
  if (!GOOGLE_CLIENT_ID) return false;
  await loadGoogleScript();
  const id = window.google?.accounts.id;
  if (!id) throw new Error("Google sign-in unavailable");
  id.initialize({
    client_id: GOOGLE_CLIENT_ID,
    callback: (res) => onCredential(res.credential),
    cancel_on_tap_outside: true,
  });
  id.renderButton(parent, {
    type: "standard",
    theme: "outline",
    size: "large",
    text: "continue_with",
    shape: "pill",
    logo_alignment: "left",
  });
  return true;
}
