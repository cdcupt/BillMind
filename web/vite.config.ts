import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev proxies the API so the web app and the Vapor server share an origin
// (no CORS in dev). In production the web app is served behind the same
// reverse proxy as the API.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/v1": { target: "http://127.0.0.1:8080", changeOrigin: true },
      "/healthz": { target: "http://127.0.0.1:8080", changeOrigin: true },
    },
  },
});
