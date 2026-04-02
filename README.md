# MBAgentKit

[简体中文](README.zh-CN.md)

A lightweight, protocol-oriented **ReAct (Reason-Act) Agent framework** for Swift.

Built for iOS 17+ / macOS 14+ with Swift 6 concurrency. Zero external dependencies in the core module.

## Features

- **ReAct Loop Engine** — Iterative reason-then-act execution with async event streaming
- **Human-In-The-Loop (HITL)** — Intercept sensitive tool calls for user approval before execution
- **Pluggable Context Compression** — Sliding window (default) or LLM-based summarization to manage conversation history
- **Sub-Agents** — Spawn child executors to delegate focused subtasks
- **Skills** — Composable bundles of system prompt + tools + configuration
- **Background Task Runner** — Manage concurrent agent runs with status tracking and cancellation
- **Protocol-Based LLM Abstraction** — Swap providers (OpenAI, DeepSeek, etc.) without changing agent logic

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  MBAgentKit (Core)               │
│                                                  │
│  AgentExecutor ←── AgentSession                  │
│       │                  │                       │
│       ├── AgentTool      ├── ContextStrategy     │
│       │   └─ BlockTool   │   ├─ SlidingWindow    │
│       │   └─ SubAgent    │   └─ Summarizing      │
│       │                  │                       │
│       ├── AgentSkill     └── AgentConfiguration  │
│       ├── AgentTaskRunner                        │
│       └── AgentEvent (async stream)              │
│                                                  │
│  LLMServiceProtocol ←── ChatMessage, Tool, ...   │
└──────────────────────┬──────────────────────────-┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
  MBAgentKitUI   MBAgentKitOpenAI   (Your LLM)
  (SwiftUI)      (MacPaw/OpenAI)
```

## Quick Start

### 1. Define Tools

```swift
import MBAgentKit

let weatherTool = BlockTool(
    name: "get_weather",
    description: "Get current weather for a city",
    parameters: ToolParameters(
        properties: [
            "city": ToolProperty(type: "string", description: "City name")
        ],
        required: ["city"]
    )
) { args in
    let city = args["city"] as? String ?? "unknown"
    return "☀️ \(city): 22°C, sunny"
}
```

### 2. Run an Agent

```swift
let executor = AgentExecutor(
    llm: myLLMService,
    tools: [weatherTool]
)

let stream = executor.run(messages: [
    .system("You are a helpful assistant with weather tools."),
    .user("What's the weather in Tokyo?")
])

for try await event in stream {
    switch event {
    case .thought(let text):  print("💭 \(text)")
    case .answer(let text):   print("✅ \(text)")
    case .toolResult(_, let name, let result):
        print("🔧 \(name): \(result)")
    default: break
    }
}
```

### 3. HITL Confirmation

Mark tools that modify data with `requiresConfirmation: true`:

```swift
let deleteTool = BlockTool(
    name: "delete_item",
    description: "Delete an item by ID",
    parameters: ToolParameters(
        properties: ["id": ToolProperty(type: "string", description: "Item ID")],
        required: ["id"]
    ),
    requiresConfirmation: true  // ← pauses for user approval
) { args in
    // ... perform deletion
    return "Deleted"
}
```

Handle the confirmation in your UI:

```swift
for try await event in stream {
    case .awaitingConfirmation(let id, let toolName, let args):
        // Show confirmation UI, then:
        executor.resume(approved: true)  // or false to reject
}
```

## Context Compression

### Problem

Long agent conversations exceed context windows. The default sliding window simply drops oldest messages, losing important context.

### Solution: Summarizing Strategy

```swift
let strategy = SummarizingStrategy(
    llm: myLLMService,    // uses a cheap LLM call to summarize
    recentToKeep: 10       // keep last 10 messages intact
)

let config = AgentConfiguration(
    sessionMaxMessages: 20,
    contextStrategy: strategy
)

let executor = AgentExecutor(
    llm: myLLMService,
    tools: myTools,
    configuration: config
)
```

**How it works:**

```
Before compression (25 messages):
[System] [User₁] [Asst₁] [Tool₁] [Result₁] ... [User₁₀] [Asst₁₀]
         ├─────── old (summarized) ────────┤     ├── recent (kept) ──┤

After compression (12 messages):
[System] [Summary of old conversation] [User₆] [Asst₆] ... [User₁₀] [Asst₁₀]
```

- Preserves key facts, decisions, and tool results in the summary
- Never splits tool-call sequences (call + result stay together)
- Falls back to sliding window if the summarization LLM call fails

### Custom Strategies

Implement `ContextStrategy` for domain-specific compression:

```swift
struct MyStrategy: ContextStrategy {
    func compress(
        messages: [ChatMessage],
        limit: Int
    ) async throws -> [ChatMessage] {
        // your logic here
    }
}
```

## Sub-Agents

Delegate subtasks to focused child agents:

```swift
let researcher = SubAgentTool(
    name: "research",
    description: "Research a topic thoroughly",
    llm: myLLMService,
    tools: [searchTool, readTool],
    systemPrompt: "You are a research assistant. Be thorough and cite sources."
)

// Parent agent can now call "research" as a tool
let executor = AgentExecutor(
    llm: myLLMService,
    tools: [researcher, writeTool]
)
```

## Skills

Pre-configured agent modes:

```swift
let codeReview = AgentSkill(
    name: "code_review",
    description: "Review code for bugs and best practices",
    systemPrompt: "You are an expert code reviewer...",
    tools: [readFileTool, searchTool],
    configuration: AgentConfiguration(maxIterations: 10)
)

// Run directly
let stream = codeReview.run(llm: myLLMService, userMessage: "Review auth.swift")

// Or use as a sub-agent tool in a parent agent
let parentTools = [codeReview.asSubAgentTool(llm: myLLMService)]
```

## Background Task Runner

Run multiple agents concurrently:

```swift
let runner = AgentTaskRunner()

let taskId = runner.submit(
    name: "Risk Analysis",
    executor: riskExecutor,
    messages: [.system("..."), .user("Analyze project risks")]
)

// Check status
if let task = runner.task(for: taskId) {
    print(task.status) // .running, .completed, .failed, etc.
}

// Cancel
runner.cancel(taskId)

// Clean up finished tasks
runner.pruneFinished()
```

## Modules

| Module | Dependencies | Purpose |
|--------|-------------|---------|
| `MBAgentKit` | None | Core engine, protocols, strategies |
| `MBAgentKitUI` | MBAgentKit | SwiftUI components (ThoughtBubble, HITLCard, etc.) |
| `MBAgentKitOpenAI` | MBAgentKit, MacPaw/OpenAI | OpenAI-compatible provider |

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "Packages/MBAgentKit")  // local
    // or .package(url: "https://github.com/user/MBAgentKit", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            "MBAgentKit",
            "MBAgentKitUI",      // optional
            "MBAgentKitOpenAI"   // optional
        ]
    )
]
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## License

MIT
