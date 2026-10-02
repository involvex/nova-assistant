/// Capabilities an [AIProvider] natively supports.
/// Mirrors the Phase-1 vision: chat, vision, streaming, embeddings (optional),
/// tool calling (optional).
enum ProviderCapability { chat, vision, streaming, embeddings, toolCalling }
