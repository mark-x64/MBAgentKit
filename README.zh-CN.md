# MBAgentKit

[English](README.md)

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

一个轻量级、面向协议的 **ReAct (Reason-Act) Agent 框架**，基于 Swift 构建。

支持 iOS 17+ / macOS 14+，使用 Swift 6 严格并发模型。核心模块零外部依赖；仅在需要 MacPaw/OpenAI SDK 集成时引入 `MBAgentKitOpenAI`。

## 功能特性

- **ReAct 循环引擎** — 迭代式推理-执行循环，以 `AsyncThrowingStream<AgentEvent>` 输出所有状态变化
- **Human-In-The-Loop (HITL)** — 拦截敏感工具调用，等待用户审批后再执行；拒绝结果会反馈回循环
- **用户输入请求** — 工具可暂停执行并直接向用户提问（文本、数字、单选、带「其他」的选择），无需 LLM 完整往返
- **置信度上报** — 工具上报 0–100 置信分，执行器发出 `.confidenceUpdated` 并同步到 `AgentRunState`
- **可插拔上下文压缩** — 滑动窗口兜底，或异步 LLM 智能摘要；绝不拆分工具调用对
- **子 Agent** — 以工具形式生成子 `AgentExecutor`，委派专注子任务
- **技能系统** — 系统提示词 + 工具 + 配置的可组合包，可独立运行或内嵌为子 Agent 工具
- **后台任务运行器** — `AgentTaskRunner` 管理并发 Agent 运行，支持状态追踪与取消
- **基于协议的 LLM 抽象** — 遵循 `LLMServiceProtocol` 即可接入任意提供商（OpenAI、DeepSeek、Ollama……）

## 架构

```
┌─────────────────────────────────────────────────┐
│                  MBAgentKit (核心)                │
│                                                  │
│  AgentExecutor ←── AgentSession                  │
│       │                  │                       │
│       ├── AgentTool      ├── ContextStrategy     │
│       │   ├─ BlockTool   │   ├─ SlidingWindow    │
│       │   └─ SubAgent    │   └─ Summarizing      │
│       │                  │                       │
│       ├── AgentSkill     └── AgentConfiguration  │
│       ├── AgentTaskRunner                        │
│       └── AgentEvent (异步事件流)                  │
│                                                  │
│  LLMServiceProtocol ←── ChatMessage, Tool, …     │
└──────────────────┬──────────────────────────────-┘
                   │
      ┌────────────┼────────────┐
      ▼            ▼            ▼
MBAgentKitUI  MBAgentKitOpenAI  (自定义 LLM)
(SwiftUI 组件)  (MacPaw/OpenAI)
```

## 模块

| 模块 | 依赖 | 用途 |
|------|------|------|
| `MBAgentKit` | 无 | 核心引擎、协议、策略 |
| `MBAgentKitUI` | MBAgentKit | SwiftUI 组件（ThoughtBubble、HITLCard、ToolCallStrip……） |
| `MBAgentKitOpenAI` | MBAgentKit, MacPaw/OpenAI | OpenAI 兼容提供商（OpenAI、DeepSeek 等） |

## 安装

### Swift Package Manager

在 Xcode 中选择 **File → Add Package Dependencies**，或在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/mark-x64/MBAgentKit", from: "1.0.0")
]
```

按需添加所需 target：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MBAgentKit", package: "MBAgentKit"),
        .product(name: "MBAgentKitUI", package: "MBAgentKit"),       // 可选
        .product(name: "MBAgentKitOpenAI", package: "MBAgentKit"),   // 可选
    ]
)
```

仅当使用 MacPaw/OpenAI SDK 时才引入 `MBAgentKitOpenAI`。`MBAgentKit` 核心与 `MBAgentKitUI` 无外部依赖。

## 快速开始

### 1. 定义工具

工具参数使用 `[String: ToolValue]` 类型，通过 `.stringValue`、`.numberValue`、`.bool`、`.array` 提取值：

```swift
import MBAgentKit

let weatherTool = BlockTool(
    name: "get_weather",
    description: "获取城市当前天气",
    parameters: ToolParameters(
        properties: [
            "city": ToolProperty(type: "string", description: "城市名称")
        ],
        required: ["city"]
    )
) { args, _ in
    let city = args["city"]?.stringValue ?? "未知"
    return "☀️ \(city): 22°C，晴"
}
```

### 2. 运行 Agent

```swift
let executor = AgentExecutor(
    llm: myLLMService,
    tools: [weatherTool]
)

let stream = executor.run(messages: [
    .system("你是一个有天气工具的助手。"),
    .user("东京天气怎么样？")
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

### 3. HITL 人工确认

将修改数据的工具标记为 `requiresConfirmation: true`：

```swift
let deleteTool = BlockTool(
    name: "delete_item",
    description: "按 ID 删除项目",
    parameters: ToolParameters(
        properties: ["id": ToolProperty(type: "string", description: "项目 ID")],
        required: ["id"]
    ),
    requiresConfirmation: true   // ← 暂停，直到 executor.resume(approved:) 被调用
) { args, _ in
    return "已删除"
}
```

处理确认事件：

```swift
case .awaitingConfirmation(let id, let toolName, let args):
    // 展示确认 UI，然后：
    executor.resume(approved: true)   // 或 false 拒绝
```

## 用户输入请求

工具可通过 `AgentToolContext` 暂停执行并直接收集用户输入，无需完整 LLM 往返：

```swift
let clarifyTool = BlockTool(
    name: "ask_budget",
    description: "询问用户的预算",
    parameters: ToolParameters(properties: [:], required: [])
) { _, context in
    guard let budget = await context.askForText(
        title: "预算确认",
        prompt: "你的预算大概是多少？",
        placeholder: "例如：5000"
    ) else { return "用户已取消。" }
    return "预算：\(budget)"
}
```

| 方法 | 说明 |
|------|------|
| `askForText(title:prompt:placeholder:)` | 自由文本输入框 |
| `askForNumber(title:prompt:placeholder:)` | 数字输入框，返回 `Double?` |
| `askForChoice(title:prompt:options:)` | 固定选项的单选选择器 |
| `askForChoiceWithOther(title:prompt:options:customPlaceholder:)` | 带「其他」自定义文本框的选择器 |

所有方法在用户取消时返回 `nil`。在 UI 中响应：

```swift
case .awaitingUserInput(_, let request):
    // request.title, request.prompt, request.kind
    // (.text, .singleChoice, .number, .choiceWithOther)
    executor.submitUserInput("用户的回答")   // 或 cancelUserInput()
```

## 置信度上报

工具通过 `context.updateConfidence(_:)` 上报 0–100 置信分，执行器发出 `.confidenceUpdated(Double)` 事件，`AgentRunState.currentConfidence` 同步更新。

```swift
let analyzeTool = BlockTool(
    name: "analyze",
    description: "分析并决策",
    parameters: ToolParameters(
        properties: ["confidence": ToolProperty(type: "number", description: "0–100")],
        required: ["confidence"]
    )
) { args, context in
    let confidence = args["confidence"]?.numberValue ?? 0
    context.updateConfidence(confidence)
    guard confidence >= 70 else { return "置信度不足——需要更多信息。" }
    return "决策：继续执行。"
}
```

## 上下文压缩

长对话会超出 LLM 上下文窗口。默认情况下 `AgentSession` 每次 append 时执行同步滑动窗口裁剪。如需更智能的压缩：

```swift
let strategy = SummarizingStrategy(
    llm: myLLMService,   // 每次压缩调用一次廉价 LLM
    recentToKeep: 10     // 保留最近 10 条消息原文
)

let config = AgentConfiguration(
    sessionMaxMessages: 20,
    contextStrategy: strategy
)
```

**工作原理：**

```
压缩前（25 条消息）：
[系统] [U₁][A₁][T₁][R₁] … [U₁₀][A₁₀]
       ├────── 将被摘要 ──────┤ ├─ 保留 ─┤

压缩后（12 条消息）：
[系统] [旧对话摘要] [U₆][A₆] … [U₁₀][A₁₀]
```

- 工具调用对（调用 + 结果）绝不被拆分
- 摘要调用失败时自动降级为滑动窗口

实现 `ContextStrategy` 协议可创建领域专属的压缩逻辑。

## 子 Agent

```swift
let researcher = SubAgentTool(
    name: "research",
    description: "深入研究某个主题",
    llm: myLLMService,
    tools: [searchTool, readTool],
    systemPrompt: "你是一个研究助手，请详尽且引用来源。"
)

let executor = AgentExecutor(llm: myLLMService, tools: [researcher, writeTool])
```

## 技能系统

预配置的 Agent 模式，可独立运行或组合为父 Agent 的子工具：

```swift
let codeReview = AgentSkill(
    name: "code_review",
    description: "审查代码中的 bug 和最佳实践",
    systemPrompt: "你是一个专业的代码审查员……",
    tools: [readFileTool, searchTool],
    configuration: AgentConfiguration(maxIterations: 10)
)

// 直接运行
let stream = codeReview.run(llm: myLLMService, userMessage: "审查 auth.swift")

// 或作为子工具嵌入父 Agent
let parentTools = [codeReview.asSubAgentTool(llm: myLLMService)]
```

## 后台任务运行器

```swift
let runner = AgentTaskRunner()

let taskId = runner.submit(
    name: "风险分析",
    executor: riskExecutor,
    messages: [.system("…"), .user("分析项目风险")]
)

print(runner.task(for: taskId)?.status)  // .running / .completed / .failed
runner.cancel(taskId)
runner.pruneFinished()
```

## MBAgentKitUI

`MBAgentKitUI` 提供统一的 `AgentRunningView`，在一个视图中渲染完整的 Agent 执行状态：思考流、工具调用时间线、HITL 确认卡片、用户输入卡片以及最终答案。

### 效果截图

| 截图 | 说明 |
|:---:|---|
| <img src="Assets/Screenshots/01-thought-running.png" width="300"> | **思考 + 工具调用中** — Agent 正在推理并派发了第一个工具调用。 |
| <img src="Assets/Screenshots/02-compact-strip.png" width="300"> | **紧凑条模式（运行中）** — 多个工具调用以水平条展示，已完成显示勾号，进行中显示旋转指示器。 |
| <img src="Assets/Screenshots/03-list-completed.png" width="300"> | **列表模式（已完成）** — 所有工具调用完成，以纵向列表展示完整结果详情。 |
| <img src="Assets/Screenshots/04-hitl-confirmation.png" width="300"> | **HITL 确认** — 敏感工具需要用户审批。展示工具名、参数及确认/取消按钮。 |
| <img src="Assets/Screenshots/05-input-text.png" width="300"> | **用户输入 — 文本** — Agent 暂停执行，向用户提出自由文本问题。 |
| <img src="Assets/Screenshots/06-input-number.png" width="300"> | **用户输入 — 数字** — 数字输入请求，使用数字键盘。 |
| <img src="Assets/Screenshots/07-input-choice.png" width="300"> | **用户输入 — 单选** — Agent 展示选项列表供用户选择。 |
| <img src="Assets/Screenshots/08-input-choice-other.png" width="300"> | **用户输入 — 单选+自定义** — 单选列表附带自由文本「其他」输入框。 |
| <img src="Assets/Screenshots/09-answer-complete.png" width="300"> | **最终答案** — 运行结束，最终答案渲染于工具调用历史下方。 |

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

| `AgentStripDisplayMode` | 说明 |
|-------------------------|------|
| `.compact` | 横向滚动条——占用空间小 |
| `.list` | 工具调用行纵向列表——展示完整细节 |

### AgentRunState

`AgentRunState` 是一个 `@Observable` 状态累加器，将执行器流中的事件喂给它，直接绑定到视图：

```swift
let runState = AgentRunState()
for try await event in executor.run(messages: messages) {
    runState.handleEvent(event)
}
```

| 属性 | 类型 | 说明 |
|------|------|------|
| `isRunning` | `Bool` | 执行器是否仍在运行 |
| `currentThought` | `String` | 最新思考增量 |
| `currentAnswer` | `String` | 累积的最终答案 |
| `events` | `[AgentEvent]` | 完整工具调用时间线 |
| `currentConfidence` | `Double?` | 工具上报的最新置信度 |
| `pendingConfirmation` | `PendingConfirmation?` | 等待 HITL 审批 |
| `pendingUserInput` | `PendingUserInput?` | 等待用户文本/选择输入 |
| `errorMessage` | `String?` | 运行失败时非空 |

## AgentEvent 参考

| 事件 | 触发时机 | 典型 UI 响应 |
|------|---------|-------------|
| `iterationStarted(n)` | 每次循环开始 | 更新迭代计数 |
| `thought(text)` | LLM 推理内容 | ThoughtBubble |
| `toolCalling(id,name,args,icon)` | 执行前 | 向时间线添加行 |
| `awaitingConfirmation(id,name,args)` | HITL 门控 | 展示 HITLConfirmationCard |
| `awaitingUserInput(id, request)` | 工具询问用户 | 展示 HITLUserInputCard |
| `confidenceUpdated(Double)` | 工具上报置信度 | 更新置信度指示器 |
| `toolResult(id,name,result,icon)` | 执行后 | 更新时间线行 |
| `answer(text)` | LLM 最终文本 | AnswerBubble |
| `completed(finalMessage)` | 运行结束 | 隐藏加载指示器 |
| `error(Error)` | 致命错误 | 错误横幅 |

## 系统要求

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## 许可证

MIT
