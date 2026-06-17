/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Google OAuth web client ID; absent → sign-in shows "not configured". */
  readonly VITE_GOOGLE_CLIENT_ID?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
