# MBAgentKit

[English](README.md)

一个轻量级、面向协议的 **ReAct (Reason-Act) Agent 框架**，基于 Swift 构建。

支持 iOS 17+ / macOS 14+，使用 Swift 6 并发模型。核心模块零外部依赖。

## 功能特性

- **ReAct 循环引擎** — 迭代式推理-执行循环，支持异步事件流
- **Human-In-The-Loop (HITL)** — 拦截敏感工具调用，等待用户审批后再执行
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
) { args in
    let city = args["city"] as? String ?? "未知"
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
) { args in
    // ... 执行删除
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
