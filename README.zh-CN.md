# MBAgentKit

[English](README.md)

<p align="center">
  <img src="Assets/MBAgentKit_Cover.jpg" alt="MBAgentKit" width="100%">
</p>

一个轻量级、面向协议的 **ReAct (Reason-Act) Agent 框架**，基于 Swift 构建。

支持 iOS 17+ / macOS 14+，使用 Swift 6 并发模型。核心模块零外部依赖。

## 功能特性

- **ReAct 循环引擎** — 迭代式推理-执行循环，支持异步事件流
- **Human-In-The-Loop (HITL)** — 拦截敏感工具调用，等待用户审批后再执行
- **用户输入请求** — 工具可以暂停执行并向用户提问（文本、单选、数字、带其他选项的选择）
- **置信度上报** — 工具上报当前置信度；执行器可将其展示给 UI，并据此决定何时向用户澄清
- **可插拔上下文压缩** — 滑动窗口（默认）或基于 LLM 的智能摘要，管理对话历史
- **子 Agent** — 生成子执行器来处理聚焦的子任务
- **技能系统** — 可组合的系统提示词 + 工具 + 配置包
- **后台任务运行器** — 管理并发 Agent 运行，支持状态追踪与取消
- **基于协议的 LLM 抽象** — 切换提供商（OpenAI、DeepSeek 等）无需修改 Agent 逻辑

## 架构

```
┌─────────────────────────────────────────────────┐
│                  MBAgentKit (核心)                │
│                                                  │
│  AgentExecutor ←── AgentSession                  │
│       │                  │                       │
│       ├── AgentTool      ├── ContextStrategy     │
│       │   └─ BlockTool   │   ├─ SlidingWindow    │
│       │   └─ SubAgent    │   └─ Summarizing      │
│       │                  │                       │
│       ├── AgentSkill     └── AgentConfiguration  │
│       ├── AgentTaskRunner                        │
│       └── AgentEvent (异步事件流)                  │
│                                                  │
│  LLMServiceProtocol ←── ChatMessage, Tool, ...   │
└──────────────────────┬──────────────────────────-┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
  MBAgentKitUI   MBAgentKitOpenAI   (自定义 LLM)
  (SwiftUI 组件)  (MacPaw/OpenAI)
```

## 快速开始

### 1. 定义工具

工具参数现在使用 `[String: ToolValue]` 类型。通过 `.stringValue`、`.numberValue`、`.bool`、`.array` 等属性提取值：

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
    return "☀️ \(city): 22°C, 晴"
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
    case .thought(let text):  print("💭 \(text)")
    case .answer(let text):   print("✅ \(text)")
    case .toolResult(_, let name, let result):
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
    requiresConfirmation: true  // ← 暂停等待用户审批
) { args, _ in
    // 仅在 executor.resume(approved: true) 后执行
    return "已删除"
}
```

在 UI 中处理确认事件：

```swift
for try await event in stream {
case .awaitingConfirmation(let id, let toolName, let args):
    // 展示确认 UI，然后：
    executor.resume(approved: true)  // 或 false 拒绝
}
```

## 用户输入请求

工具可以暂停执行并直接向用户提问，无需通过 LLM 完整往返。使用 `BlockTool` 闭包第二个参数 `AgentToolContext`：

```swift
let clarifyTool = BlockTool(
    name: "ask_budget",
    description: "询问用户的预算",
    parameters: ToolParameters(properties: [:], required: [])
) { _, context in
    // 自由文本输入
    guard let budget = await context.askForText(
        title: "预算确认",
        prompt: "你的预算大概是多少？",
        placeholder: "例如：5000"
    ) else { return "用户已取消。" }
    return "预算：\(budget)"
}
```

### 可用输入方法

| 方法 | 说明 |
|------|------|
| `askForText(title:prompt:placeholder:)` | 自由文本输入框 |
| `askForNumber(title:prompt:placeholder:)` | 数字输入框，返回 `Double?` |
| `askForChoice(title:prompt:options:)` | 固定选项的单选选择器 |
| `askForChoiceWithOther(title:prompt:options:customPlaceholder:)` | 带「其他」自定义文本框的选择器 |

所有方法在用户取消时返回 `nil`。

### 在 UI 中处理

执行器会发出 `.awaitingUserInput` 和 `.userInputResolved` 事件。使用 `MBAgentKitUI` 的 `AgentRunningView` 时这些事件会自动处理。自定义 UI 时响应：

```swift
case .awaitingUserInput(let id, let request):
    // request.title, request.prompt, request.kind
    // (.text, .singleChoice, .number, .choiceWithOther)
    executor.submitUserInput("用户的回答")   // 或 cancelUserInput()
```

## 置信度上报

工具可以通过 `context.updateConfidence(_:)` 上报当前置信度。执行器会将其作为 `.confidenceUpdated(Double)` 事件发出，并体现在 `AgentRunState.currentConfidence` 中。

常见模式：以低置信度为门控来触发澄清：

```swift
let analyzeTool = BlockTool(
    name: "analyze",
    description: "分析并决策",
    parameters: ToolParameters(
        properties: [
            "confidence": ToolProperty(type: "number", description: "0–100")
        ],
        required: ["confidence"]
    )
) { args, context in
    let confidence = args["confidence"]?.numberValue ?? 0
    context.updateConfidence(confidence)

    guard confidence >= 70 else {
        return "置信度不足——需要更多信息。"
    }
    return "决策：继续执行。"
}
```

## 上下文压缩

### 问题

长对话会超出上下文窗口限制。默认滑动窗口只是丢弃最早的消息，会丢失重要上下文。

### 解决方案：摘要策略

```swift
let strategy = SummarizingStrategy(
    llm: myLLMService,    // 使用一次廉价的 LLM 调用来生成摘要
    recentToKeep: 10       // 保留最近 10 条消息不变
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

**工作原理：**

```
压缩前（25 条消息）：
[系统] [用户₁] [助手₁] [工具₁] [结果₁] ... [用户₁₀] [助手₁₀]
       ├────── 旧消息（将被摘要）──────┤     ├── 近期（保留）──┤

压缩后（12 条消息）：
[系统] [旧对话摘要] [用户₆] [助手₆] ... [用户₁₀] [助手₁₀]
```

- 在摘要中保留关键事实、决策和工具结果
- 不会拆分工具调用序列（调用 + 结果保持在一起）
- 如果摘要 LLM 调用失败，自动降级为滑动窗口

### 自定义策略

实现 `ContextStrategy` 协议来创建特定领域的压缩逻辑：

```swift
struct MyStrategy: ContextStrategy {
    func compress(
        messages: [ChatMessage],
        limit: Int
    ) async throws -> [ChatMessage] {
        // 自定义压缩逻辑
    }
}
```

## 子 Agent

将子任务委派给聚焦的子 Agent：

```swift
let researcher = SubAgentTool(
    name: "research",
    description: "深入研究某个主题",
    llm: myLLMService,
    tools: [searchTool, readTool],
    systemPrompt: "你是一个研究助手，请详尽且引用来源。"
)

// 父 Agent 现在可以调用 "research" 作为工具
let executor = AgentExecutor(
    llm: myLLMService,
    tools: [researcher, writeTool]
)
```

## 技能系统

预配置的 Agent 模式：

```swift
let codeReview = AgentSkill(
    name: "code_review",
    description: "审查代码中的 bug 和最佳实践",
    systemPrompt: "你是一个专业的代码审查员...",
    tools: [readFileTool, searchTool],
    configuration: AgentConfiguration(maxIterations: 10)
)

// 直接运行
let stream = codeReview.run(llm: myLLMService, userMessage: "审查 auth.swift")

// 或作为子 Agent 工具在父 Agent 中使用
let parentTools = [codeReview.asSubAgentTool(llm: myLLMService)]
```

## 后台任务运行器

并发运行多个 Agent：

```swift
let runner = AgentTaskRunner()

let taskId = runner.submit(
    name: "风险分析",
    executor: riskExecutor,
    messages: [.system("..."), .user("分析项目风险")]
)

// 查看状态
if let task = runner.task(for: taskId) {
    print(task.status) // .running, .completed, .failed 等
}

// 取消任务
runner.cancel(taskId)

// 清理已完成的任务
runner.pruneFinished()
```

## MBAgentKitUI

`MBAgentKitUI` 提供统一的 `AgentRunningView`，在一个视图中渲染完整的 Agent 执行状态——思考过程、工具调用时间线、HITL 确认卡片、用户输入卡片以及最终答案。

### 效果截图

| 截图 | 说明 |
|:---:|---|
| <img src="Assets/Screenshots/01-thought-running.png" width="300"> | **思考 + 工具调用中** — Agent 正在推理并派发了第一个工具调用。紧凑条显示进行中工具的旋转指示器。 |
| <img src="Assets/Screenshots/02-compact-strip.png" width="300"> | **紧凑条模式（运行中）** — 多个工具调用以水平条展示。已完成的显示勾号，进行中的显示旋转指示器。 |
| <img src="Assets/Screenshots/03-list-completed.png" width="300"> | **列表模式（已完成）** — 所有工具调用完成，以纵向列表展示完整的结果详情。 |
| <img src="Assets/Screenshots/04-hitl-confirmation.png" width="300"> | **HITL 确认** — 敏感工具（`send_email`）需要用户审批才能执行。展示工具名、参数以及确认/取消按钮。 |
| <img src="Assets/Screenshots/05-input-text.png" width="300"> | **用户输入 — 文本** — Agent 暂停执行，向用户提出自由文本问题。 |
| <img src="Assets/Screenshots/06-input-number.png" width="300"> | **用户输入 — 数字** — 数字输入请求，使用数字键盘。 |
| <img src="Assets/Screenshots/07-input-choice.png" width="300"> | **用户输入 — 单选** — Agent 展示选项列表供用户选择。 |
| <img src="Assets/Screenshots/08-input-choice-other.png" width="300"> | **用户输入 — 单选+自定义** — 单选列表附带一个自由文本「其他」输入框。 |
| <img src="Assets/Screenshots/09-answer-complete.png" width="300"> | **最终答案** — Agent 运行结束，展示最终答案，上方附带工具调用历史。 |

### AgentRunningView

```swift
import MBAgentKitUI

// 持久化显示模式偏好（紧凑横向条 vs. 完整列表）
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
    onConfirm: { executor.resume(approved: true) },
    onReject:  { executor.resume(approved: false) },
    onSubmitInput: { executor.submitUserInput($0) },
    onCancelInput: { executor.cancelUserInput() }
)
```

`AgentStripDisplayMode` 控制工具调用进度的展示方式：

| 值 | 说明 |
|----|------|
| `.compact` | 横向滚动条——占用空间小 |
| `.list` | 工具调用行的纵向列表——展示完整细节 |

调用方持有并持久化 `displayMode`。用 `@AppStorage` 支持可跨启动保留偏好设置。

### AgentRunState

`AgentRunState` 是一个 `@Observable` 状态累加器。将执行器流中的事件喂给它，直接绑定到视图：

```swift
let runState = AgentRunState()

for try await event in executor.run(messages: messages) {
    runState.handleEvent(event)
}
```

核心属性：

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

## 模块

| 模块 | 依赖 | 用途 |
|------|------|------|
| `MBAgentKit` | 无 | 核心引擎、协议、策略 |
| `MBAgentKitUI` | MBAgentKit | SwiftUI 组件（ThoughtBubble、HITLCard 等） |
| `MBAgentKitOpenAI` | MBAgentKit, MacPaw/OpenAI | OpenAI 兼容提供商 |

## 安装

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(path: "Packages/MBAgentKit")  // 本地引用
    // 或 .package(url: "https://github.com/user/MBAgentKit", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            "MBAgentKit",
            "MBAgentKitUI",      // 可选
            "MBAgentKitOpenAI"   // 可选
        ]
    )
]
```

## 系统要求

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## 许可证

MIT
