//
//  DisableThinkingMiddleware.swift
//  MBAgentKitOpenAI
//
//  某些 LLM（如 Kimi K2.5、DeepSeek）默认启用 thinking/reasoning 模式，
//  要求会话历史中的 assistant 消息携带 reasoning_content 字段。
//  本框架不维护该字段，因此通过中间件在请求体中注入
//  `"thinking": {"type": "disabled"}` 来关闭 thinking 模式。

import Foundation
import OpenAI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct DisableThinkingMiddleware: OpenAIMiddleware {
    func intercept(request: URLRequest) -> URLRequest {
        // 仅拦截 chat/completions 请求
        guard let url = request.url,
              url.path.contains("chat/completions"),
              let body = request.httpBody else {
            return request
        }

        guard var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return request
        }

        // 注入 thinking: disabled（兼容 Kimi / DeepSeek 等支持此参数的 provider）
        json["thinking"] = ["type": "disabled"]

        guard let newBody = try? JSONSerialization.data(withJSONObject: json) else {
            return request
        }

        var modified = request
        modified.httpBody = newBody
        return modified
    }
}
