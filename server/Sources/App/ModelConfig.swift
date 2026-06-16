import Vapor

/// Central AI-model configuration. Every model the app uses is named here and
/// overridable by an environment variable, so changing models is a config change
/// (env var + container recreate), never a code change or rebuild.
///
/// Defaults track the current best choice per task. Latest options seen on the
/// account (2026-06):
///   - Gemini (capture + agent): gemini-3-flash-preview (Gemini 3, preview),
///     gemini-2.5-flash (GA/stable). Use a `-preview` only knowingly — Google can
///     change or retire it; flip `GEMINI_MODEL` back to gemini-2.5-flash if so.
///   - OpenAI moderation: omni-moderation-latest (auto-updating alias).
///   - OpenAI image (icons/mascots, build-time tooling — not the server runtime):
///     gpt-image-2.
struct ModelConfig {
    /// Gemini powers all live AI in the app — typed capture, photo recognition,
    /// and the conversational agent.
    let gemini: String
    /// Gemini image generation — the Minds infographic (server-side, the app's
    /// own key). `gemini-3.1-flash-image` is GA; image gen can take 60–120s.
    let geminiImage: String
    /// OpenAI's dedicated safety classifier; guards every user input before it
    /// reaches Gemini.
    let moderation: String

    static func fromEnvironment() -> ModelConfig {
        ModelConfig(
            gemini: Environment.get("GEMINI_MODEL") ?? "gemini-3-flash-preview",
            geminiImage: Environment.get("GEMINI_IMAGE_MODEL") ?? "gemini-3.1-flash-image",
            moderation: Environment.get("OPENAI_MODERATION_MODEL") ?? "omni-moderation-latest"
        )
    }
}
