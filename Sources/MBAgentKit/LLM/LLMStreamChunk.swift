//
//  LLMStreamChunk.swift
//  MBAgentKit
//
//  Token-level streaming parts emitted by ``LLMServiceProtocol/streamChatCompletionWithTools(messages:tools:temperature:)``.
//  Modeled after Vercel AI SDK 6's `fullStream` parts, simplified for OpenAI-style
//  Chat Completion streams (text deltas, optional reasoning deltas, tool-call deltas).
//

import Foundation

/// A single delta chunk produced during a streaming chat completion.
///
/// The accumulated chunks across a stream are equivalent to one ``ToolCallResponse``:
/// - All ``LLMStreamChunk/textDelta(_:)`` concatenated form `.text(...)`.
/// - All ``LLMStreamChunk/toolCallDelta(index:id:name:argumentsDelta:)`` merged by
///   `index` form `.toolCalls([...])`.
/// - ``LLMStreamChunk/finish(reason:)`` carries the OpenAI `finish_reason`.
public enum LLMStreamChunk: Sendable {
    /// Incremental assistant text. Always append.
    case textDelta(String)

    /// Reasoning trace from providers that expose it
    /// (DeepSeek `reasoning_content`, Gemini/OpenRouter `reasoning`).
    /// Append-only. Distinct from the final answer text.
    case reasoningDelta(String)

    /// Streaming tool-call slice. The same `index` may appear in many chunks —
    /// callers must merge `id` / `name` / `argumentsDelta` by `index`.
    /// `id` and `name` typically arrive in the first chunk for that index;
    /// `argumentsDelta` is appended over many chunks.
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsDelta: String?)

    /// End-of-stream marker carrying the OpenAI `finish_reason`
    /// (`"stop"`, `"tool_calls"`, `"length"`, etc.).
    case finish(reason: String?)
}
