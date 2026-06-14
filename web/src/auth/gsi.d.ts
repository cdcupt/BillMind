// Minimal typings for the Google Identity Services client
// (https://accounts.google.com/gsi/client) — only the surface we use.

interface GsiCredentialResponse {
  credential: string; // the ID token (JWT) to exchange with the server
  select_by?: string;
}

interface GsiIdConfiguration {
  client_id: string;
  callback: (response: GsiCredentialResponse) => void;
  auto_select?: boolean;
  cancel_on_tap_outside?: boolean;
  use_fedcm_for_prompt?: boolean;
}

interface GsiButtonConfiguration {
  type?: "standard" | "icon";
  theme?: "outline" | "filled_blue" | "filled_black";
  size?: "large" | "medium" | "small";
  text?: "signin_with" | "signup_with" | "continue_with" | "signin";
  shape?: "rectangular" | "pill" | "circle" | "square";
  logo_alignment?: "left" | "center";
  width?: number;
}

interface Window {
  google?: {
    accounts: {
      id: {
        initialize: (config: GsiIdConfiguration) => void;
        renderButton: (parent: HTMLElement, options: GsiButtonConfiguration) => void;
        prompt: () => void;
        disableAutoSelect: () => void;
      };
    };
  };
}
