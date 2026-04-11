# MBAgentKit

[简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/MBAgentKit_Cover.jpg" alt="MBAgentKit" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-17%2B-007AFF?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/macOS-14%2B-007AFF?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/SPM-compatible-34C759" alt="SPM compatible">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="MIT License">
</p>

A lightweight, protocol-oriented **ReAct (Reason-Act) Agent framework** for Swift.

Built for iOS 17+ / macOS 14+ with Swift 6 strict concurrency. The core module has zero external dependencies — add `MBAgentKitOpenAI` only if you need the MacPaw/OpenAI SDK integration.

## Features

- **ReAct Loop Engine** — Iterative reason-then-act execution with `AsyncThrowingStream<AgentEvent>` output
- **Human-In-The-Loop (HITL)** — Intercept sensitive tool calls for user approval before execution; rejection feeds back into the loop
- **User Input Requests** — Tools can pause execution and ask the user a question (text, number, single-choice, choice-with-other, slider) without a full LLM round-trip
- **Confidence Reporting** — Tools report a 0–100 confidence score; the executor emits `.confidenceUpdated` and surfaces it in `AgentRunState`
- **Pluggable Context Compression** — Sliding-window fallback or async LLM-based summarization; never orphans tool-call pairs
- **Sub-Agents** — Spawn child `AgentExecutor` instances as tools to delegate focused subtasks
- **Skills** — Composable bundles of system prompt + tools + configuration, usable standalone or as sub-agent tools
- **Background Task Runner** — `AgentTaskRunner` manages concurrent agent runs with status tracking and cancellation
- **Protocol-Based LLM Abstraction** — Swap providers (OpenAI, DeepSeek, Ollama, …) by conforming to `LLMServiceProtocol`

## Architecture

```
┌──────────────────────────────────────────────────┐
│                  MBAgentKit (Core)               │
│                                                  │
│  AgentExecutor ←── AgentSession                  │
│       │                  │                       │
│       ├── AgentTool      ├── ContextStrategy     │
│       │   ├─ BlockTool   │   ├─ SlidingWindow    │
│       │   └─ SubAgent    │   └─ Summarizing      │
│       │                  │                       │
│       ├── AgentSkill     └── AgentConfiguration  │
│       ├── AgentTaskRunner                        │
│       └── AgentEvent (async stream)              │
│                                                  │
│  LLMServiceProtocol ←── ChatMessage, Tool, …     │
└──────────────────┬───────────────────────────────┘
                   │
      ┌────────────┼────────────┐
      ▼            ▼            ▼
MBAgentKitUI  MBAgentKitOpenAI  (Your LLM)
(SwiftUI)     (MacPaw/OpenAI)
```

## Modules

| Module | Dependencies | Purpose |
|--------|-------------|---------|
| `MBAgentKit` | None | Core engine, protocols, strategies |
| `MBAgentKitUI` | MBAgentKit | SwiftUI components (ThoughtBubble, HITLCard, ToolCallStrip, …) |
| `MBAgentKitOpenAI` | MBAgentKit, MacPaw/OpenAI | OpenAI-compatible provider (OpenAI, DeepSeek, etc.) |

## Installation

### Swift Package Manager

Add the package in Xcode via **File → Add Package Dependencies**, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mark-x64/MBAgentKit", from: "1.0.0")
]
```

Then add the targets you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MBAgentKit", package: "MBAgentKit"),
        .product(name: "MBAgentKitUI", package: "MBAgentKit"),       // optional
        .product(name: "MBAgentKitOpenAI", package: "MBAgentKit"),   // optional
    ]
)
```

Only import `MBAgentKitOpenAI` if you are using the MacPaw/OpenAI SDK. `MBAgentKit` core and `MBAgentKitUI` have no external dependencies.

## Quick Start

### 1. Define Tools

Tool arguments are typed as `[String: ToolValue]`. Use `.stringValue`, `.numberValue`, `.bool`, `.array` to extract values:

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
) { args, _ in
    let city = args["city"]?.stringValue ?? "unknown"
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
    case .thought(let text):       print("💭 \(text)")
    case .answer(let text):        print("✅ \(text)")
    case .toolResult(_, let name, let result, _):
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
    requiresConfirmation: true   // ← suspends until executor.resume(approved:) is called
) { args, _ in
    return "Deleted"
}
```

Handle the confirmation event:

```swift
case .awaitingConfirmation(let id, let toolName, let args):
    // Present confirmation UI, then:
    executor.resume(approved: true)   // or false to reject
```

## User Input Requests

Tools can pause execution and collect user input directly via `AgentToolContext`, without a full LLM round-trip:

```swift
let clarifyTool = BlockTool(
    name: "ask_budget",
    description: "Ask the user for their budget",
    parameters: ToolParameters(properties: [:], required: [])
) { _, context in
    guard let budget = await context.askForText(
        title: "Budget",
        prompt: "What is your budget?",
        placeholder: "e.g. 5000"
    ) else { return "User cancelled." }
    return "Budget: \(budget)"
}
```

| Method | Description |
|--------|-------------|
| `askForText(title:prompt:placeholder:)` | Free-text field |
| `askForNumber(title:prompt:placeholder:)` | Numeric field, returns `Double?` |
| `askForChoice(title:prompt:options:)` | Single-choice picker |
| `askForChoiceWithOther(title:prompt:options:customPlaceholder:)` | Choice picker with an additional free-text "other" field |
| `askForSlider(title:prompt:min:max:step:defaultValue:unit:labels:)` | Numeric slider (continuous or stepped, with optional tick labels), returns `Double?` |

All methods return `nil` if the user cancels. Handle in the UI with:

```swift
case .awaitingUserInput(_, let request):
    // request.title, request.prompt, request.kind
    // (.text, .singleChoice, .number, .choiceWithOther, .slider)
    executor.submitUserInput("user's answer")   // or cancelUserInput()
```

## Confidence Reporting

Tools report a 0–100 confidence level via `context.updateConfidence(_:)`. The executor emits `.confidenceUpdated(Double)` and `AgentRunState.currentConfidence` stays in sync.

```swift
let analyzeTool = BlockTool(
    name: "analyze",
    description: "Analyze and decide",
    parameters: ToolParameters(
        properties: ["confidence": ToolProperty(type: "number", description: "0–100")],
        required: ["confidence"]
    )
) { args, context in
    let confidence = args["confidence"]?.numberValue ?? 0
    context.updateConfidence(confidence)
    guard confidence >= 70 else { return "Confidence too low — need more information." }
    return "Decision: proceed."
}
```

## Context Compression

Long agent conversations exceed LLM context windows. By default, `AgentSession` applies a sync sliding-window trim on every append. For smarter compression:

```swift
let strategy = SummarizingStrategy(
    llm: myLLMService,   // one inexpensive LLM call per compression
    recentToKeep: 10     // keep the last 10 messages verbatim
)

let config = AgentConfiguration(
    sessionMaxMessages: 20,
    contextStrategy: strategy
)
```

**How it works:**

```
Before (25 messages):
[System] [U₁][A₁][T₁][R₁] … [U₁₀][A₁₀]
         ├────── summarised ──────┤ ├─ kept ─┤

After (12 messages):
[System] [Summary of earlier conversation] [U₆][A₆] … [U₁₀][A₁₀]
```

- Tool-call pairs (call + result) are never split
- Falls back to sliding window if the summarisation call fails

Implement `ContextStrategy` for domain-specific compression logic.

## Sub-Agents

```swift
let researcher = SubAgentTool(
    name: "research",
    description: "Research a topic thoroughly",
    llm: myLLMService,
    tools: [searchTool, readTool],
    systemPrompt: "You are a research assistant. Be thorough and cite sources."
)

let executor = AgentExecutor(llm: myLLMService, tools: [researcher, writeTool])
```

## Skills

Pre-configured agent modes, usable standalone or embedded as sub-agent tools:

```swift
let codeReview = AgentSkill(
    name: "code_review",
    description: "Review code for bugs and best practices",
    systemPrompt: "You are an expert code reviewer…",
    tools: [readFileTool, searchTool],
    configuration: AgentConfiguration(maxIterations: 10)
)

// Run directly
let stream = codeReview.run(llm: myLLMService, userMessage: "Review auth.swift")

// Or compose into a parent agent
let parentTools = [codeReview.asSubAgentTool(llm: myLLMService)]
```

## Background Task Runner

```swift
let runner = AgentTaskRunner()

let taskId = runner.submit(
    name: "Risk Analysis",
    executor: riskExecutor,
    messages: [.system("…"), .user("Analyze project risks")]
)

print(runner.task(for: taskId)?.status)  // .running / .completed / .failed
runner.cancel(taskId)
runner.pruneFinished()
```

## MBAgentKitUI

`MBAgentKitUI` provides `AgentRunningView` — a single view that renders the full agent execution state: thought stream, tool call timeline, HITL confirmation cards, user input cards, and the final answer.

### Screenshots

| Screenshot | Description |
|:---:|---|
| <img src="Assets/Screenshots/01-thought-running.png" width="300"> | **Thought + Tool Calling** — Reasoning in progress; compact strip shows the in-flight tool call. |
| <img src="Assets/Screenshots/02-compact-strip.png" width="300"> | **Compact Strip (Running)** — Multiple tool calls in a horizontal scrolling strip. Completed tools show checkmarks; active tool shows a spinner. |
| <img src="Assets/Screenshots/03-list-completed.png" width="300"> | **List Mode (Completed)** — All tool calls finished, displayed as a vertical list with full result details. |
| <img src="Assets/Screenshots/04-hitl-confirmation.png" width="300"> | **HITL Confirmation** — A sensitive tool requires approval. Shows tool name, arguments, and Confirm / Cancel. |
| <img src="Assets/Screenshots/05-input-text.png" width="300"> | **User Input — Text** — Agent pauses to collect a free-text answer from the user. |
| <img src="Assets/Screenshots/06-input-number.png" width="300"> | **User Input — Number** — Numeric input with decimal keypad. |
| <img src="Assets/Screenshots/07-input-choice.png" width="300"> | **User Input — Single Choice** — Agent presents a list of options. |
| <img src="Assets/Screenshots/08-input-choice-other.png" width="300"> | **User Input — Choice + Custom** — Choice list with an additional free-text "other" field. |
| <img src="Assets/Screenshots/09-answer-complete.png" width="300"> | **Final Answer** — Run complete; final answer rendered below the tool call history. |

### AgentRunningView

```swift
import MBAgentKitUI

@AppStorage("agentStripDisplayMode") var displayMode: AgentStripDisplayMode = .compact

AgentRunningView(
    thought: runState.currentThought,
    events: runState.events,
    answer: runState.currentAnswer,
    isRunning: runState.isRunning,
    iterationCount: runState.iterationCount,
    pendingConfirmation: runState.pendingConfirmation,
    pendingUserInput: runState.pendingUserInput,
    displayMode: $displayMode,
    onConfirm:     { executor.resume(approved: true) },
    onReject:      { executor.resume(approved: false) },
    onSubmitInput: { executor.submitUserInput($0) },
    onCancelInput: { executor.cancelUserInput() }
)
```

| `AgentStripDisplayMode` | Description |
|-------------------------|-------------|
| `.compact` | Horizontal scrolling strip — minimal footprint |
| `.list` | Vertical list of tool call rows — full detail |

### AgentRunState

`AgentRunState` is an `@Observable` accumulator. Feed it events and bind it directly to your views:

```swift
let runState = AgentRunState()
for try await event in executor.run(messages: messages) {
    runState.handleEvent(event)
}
```

| Property | Type | Description |
|----------|------|-------------|
| `isRunning` | `Bool` | Executor still active |
| `currentThought` | `String` | Latest thought delta |
| `currentAnswer` | `String` | Accumulated final answer |
| `events` | `[AgentEvent]` | Full tool call timeline |
| `currentConfidence` | `Double?` | Latest confidence reported by a tool |
| `pendingConfirmation` | `PendingConfirmation?` | Awaiting HITL approval |
| `pendingUserInput` | `PendingUserInput?` | Awaiting user text/choice input |
| `errorMessage` | `String?` | Non-nil if the run failed |

## AgentEvent Reference

| Event | Trigger | Typical UI response |
|-------|---------|---------------------|
| `iterationStarted(n)` | Each loop start | Increment counter |
| `thought(text)` | LLM reasoning content | ThoughtBubble |
| `toolCalling(id,name,args,icon)` | Before execution | Add row to timeline |
| `awaitingConfirmation(id,name,args)` | HITL gate | Show HITLConfirmationCard |
| `awaitingUserInput(id, request)` | Tool asks user | Show HITLUserInputCard |
| `confidenceUpdated(Double)` | Tool reports confidence | Update indicator |
| `toolResult(id,name,result,icon)` | After execution | Update timeline row |
| `answer(text)` | LLM final text | AnswerBubble |
| `completed(finalMessage)` | Run finished | Hide spinner |
| `error(Error)` | Fatal error | Error banner |

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## License

MIT
