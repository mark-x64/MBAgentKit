//
//  ChatMessage.swift
//  MBAgentKit
//

import Foundation

/// Role of a chat message in an LLM conversation.
public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    /// Function-calling tool result message.
    case tool
}

/// An image attachment for Vision-capable LLMs.
public struct ImagePart: Codable, Sendable {
    /// JPEG-compressed image data.
    public let data: Data
    /// MIME type, e.g. "image/jpeg".
    public let mediaType: String

    public init(data: Data, mediaType: String = "image/jpeg") {
        self.data = data
        self.mediaType = mediaType
    }
}

/// A single message in an LLM conversation, compatible with OpenAI-style APIs.
///
/// - `content` is `String?` because an assistant message carrying `toolCalls`
///   may have `nil` content.
/// - `toolCalls` is present when the LLM requests tool execution.
/// - `toolCallId` correlates a tool-result message back to the original call.
/// - `imageParts` carries image attachments for Vision-capable LLMs (user messages only).
public struct ChatMessage: Codable, Sendable {
    public let role: ChatRole
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let imageParts: [ImagePart]?

    public enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case imageParts = "image_parts"
    }

    // MARK: - Basic init

    public init(role: ChatRole, content: String?) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallId = nil
        self.imageParts = nil
    }

    // MARK: - Static Factories

    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    /// Construct a user message with text and image attachments (for Vision-capable LLMs).
    public static func userWithImages(_ content: String, images: [ImagePart]) -> ChatMessage {
        ChatMessage(role: .user, content: content, toolCalls: nil, toolCallId: nil, imageParts: images)
    }

    /// Construct an assistant message carrying tool calls (content may be nil).
    public static func assistantWithToolCalls(_ toolCalls: [ToolCall]) -> ChatMessage {
        ChatMessage(role: .assistant, content: nil, toolCalls: toolCalls, toolCallId: nil)
    }

    /// Construct a tool-result message correlated by `id`.
    public static func toolResult(id: String, content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCalls: nil, toolCallId: id)
    }

    // MARK: - Full init (internal factory use)

    private init(role: ChatRole, content: String?, toolCalls: [ToolCall]?, toolCallId: String?, imageParts: [ImagePart]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.imageParts = imageParts
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(imageParts, forKey: .imageParts)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        imageParts = try container.decodeIfPresent([ImagePart].self, forKey: .imageParts)
    }
}
