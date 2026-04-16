//
//  CompactToolCallStrip.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

// MARK: - Pill Data

private struct ToolPillData: Identifiable {
    let id: String
    let name: String
    let result: String?
    let iconName: String?
    var isCompleted: Bool { result != nil }
}

// MARK: - Compact Strip

public struct CompactToolCallStrip: View {
    public let events: [AgentEvent]

    public init(events: [AgentEvent]) {
        self.events = events
    }

    private var pills: [ToolPillData] {
        events.compactMap { event in
            switch event {
            case .toolCalling(let id, let name, _, let iconName):
                return ToolPillData(id: id, name: name, result: nil, iconName: iconName)
            case .toolResult(let id, let name, let result, let iconName):
                return ToolPillData(id: id, name: name, result: result, iconName: iconName)
            default:
                return nil
            }
        }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(pills) { pill in
                        ToolPill(data: pill)
                            .id(pill.id)
                            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .animation(.snappy, value: pills.count)
            }
            .onAppear { scrollToTrailing(proxy) }
            .onChange(of: events.count) { scrollToTrailing(proxy) }
        }
    }

    private func scrollToTrailing(_ proxy: ScrollViewProxy) {
        guard let last = pills.last else { return }
        withAnimation(.snappy) {
            proxy.scrollTo(last.id, anchor: .trailing)
        }
    }
}

// MARK: - Tool Pill

private struct ToolPill: View {
    let data: ToolPillData
    @State private var isExpanded = false

    /// 优先用工具自身声明的 iconName，否则用通用 fallback。
    private var resolvedIcon: String {
        data.iconName ?? "wrench"
    }

    // 调用中 或 已完成且已展开 时显示名称
    private var showName: Bool { !data.isCompleted || isExpanded }

    var body: some View {
        Button {
            guard data.isCompleted else { return }
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: showName ? 5 : 0) {
                // 图标区（固定 14×14，保证折叠时水平内边距=垂直内边距 → Capsule 呈圆形）
                ZStack {
                    if data.isCompleted {
                        Image(systemName: resolvedIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .frame(width: 14, height: 14)

                // 工具名（calling 或 expanded）
                if showName {
                    Text(data.name)
                        .font(.system(size: 11, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .blurReplace))
                }
            }
            .padding(.horizontal, showName ? 10 : 8)
            .padding(.vertical, 8)
            .background(.thickMaterial, in: Capsule())
            .overlay {
                if isExpanded {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.18), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isExpanded)
        .animation(.snappy, value: data.isCompleted)
        // 完成时先保持展开 1 秒，让用户看到工具名，再收起为紧凑圆点
        .onChange(of: data.isCompleted) { _, completed in
            guard completed else { return }
            isExpanded = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.snappy) { isExpanded = false }
            }
        }
    }
}

// MARK: - Preview

#Preview("Compact Strip", traits: .sizeThatFitsLayout) {
    @Previewable @State var events: [AgentEvent] = [
        .toolResult(id: "1", name: "get_balance_info", result: "招商银行 ¥34,120 / 支付宝 ¥32,050", iconName: "banknote"),
        .toolResult(id: "2", name: "get_items_info",   result: "MacBook Pro 14、Sony A7C II",       iconName: "tray.full"),
        .toolResult(id: "3", name: "web_search",       result: "iPhone 16 Pro 最低 ¥7,999",          iconName: "magnifyingglass"),
        .toolCalling(id: "4", name: "fetch_webpage",   arguments: .empty,                            iconName: "link"),
    ]

    VStack(spacing: 20) {
        CompactToolCallStrip(events: events)
            .padding(.horizontal)

        HStack(spacing: 12) {
            Button("追加 calling") {
                let id = UUID().uuidString
                events.append(.toolCalling(id: id, name: "get_bills", arguments: .empty, iconName: "doc.text"))
            }
            .buttonStyle(.bordered)

            Button("最后一条 → completed") {
                guard case .toolCalling(let id, let name, _, let icon) = events.last else { return }
                events[events.count - 1] = .toolResult(id: id, name: name, result: "每月固定支出 ¥5,459", iconName: icon)
            }
            .buttonStyle(.bordered)
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
