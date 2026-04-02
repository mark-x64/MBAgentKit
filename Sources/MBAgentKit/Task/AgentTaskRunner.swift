//
//  AgentTaskRunner.swift
//  MBAgentKit
//

import Foundation

/// Manages background agent runs, allowing multiple agents to execute
/// concurrently with status tracking and cancellation support.
///
/// ```swift
/// let runner = AgentTaskRunner()
///
/// let taskId = runner.submit(
///     name: "Analyze risks",
///     executor: executor,
///     messages: [.system("..."), .user("Analyze project risks")]
/// )
///
/// // Check status
/// if let task = runner.task(for: taskId) {
///     print(task.status) // .running
/// }
///
/// // Cancel if needed
/// runner.cancel(taskId)
/// ```
@Observable
public final class AgentTaskRunner: @unchecked Sendable {

    // MARK: - Types

    /// A tracked background agent task.
    public struct AgentTask: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public var status: Status
        public var result: String?

        public enum Status: Sendable, Equatable {
            case pending
            case running
            case completed
            case cancelled
            case failed(String)
        }
    }

    // MARK: - State

    public private(set) var tasks: [AgentTask] = []
    private var handles: [UUID: Task<Void, Never>] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Public API

    /// Submit an agent run as a background task.
    ///
    /// - Returns: The task ID for status queries or cancellation.
    @discardableResult
    public func submit(
        name: String,
        executor: AgentExecutor,
        messages: [ChatMessage]
    ) -> UUID {
        let taskId = UUID()
        let agentTask = AgentTask(id: taskId, name: name, status: .pending, result: nil)

        lock.lock()
        tasks.append(agentTask)
        lock.unlock()

        let handle = Task { [weak self] in
            self?.updateStatus(taskId, .running)

            let stream = executor.run(messages: messages)
            var finalResult = ""

            do {
                for try await event in stream {
                    if case .answer(let text) = event {
                        finalResult = text
                    }
                }
                self?.complete(taskId, result: finalResult)
            } catch {
                if Task.isCancelled {
                    self?.updateStatus(taskId, .cancelled)
                } else {
                    self?.updateStatus(taskId, .failed(error.localizedDescription))
                }
            }
        }

        lock.lock()
        handles[taskId] = handle
        lock.unlock()

        return taskId
    }

    /// Cancel a running task.
    public func cancel(_ taskId: UUID) {
        lock.lock()
        handles[taskId]?.cancel()
        handles[taskId] = nil
        lock.unlock()
        updateStatus(taskId, .cancelled)
    }

    /// Look up a task by ID.
    public func task(for id: UUID) -> AgentTask? {
        lock.lock()
        defer { lock.unlock() }
        return tasks.first { $0.id == id }
    }

    /// Remove completed/cancelled/failed tasks from the list.
    public func pruneFinished() {
        lock.lock()
        let activeIds = tasks.filter {
            $0.status == .pending || $0.status == .running
        }.map(\.id)
        tasks.removeAll { !activeIds.contains($0.id) }
        handles = handles.filter { activeIds.contains($0.key) }
        lock.unlock()
    }

    // MARK: - Private

    private func updateStatus(_ taskId: UUID, _ status: AgentTask.Status) {
        lock.lock()
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].status = status
        }
        lock.unlock()
    }

    private func complete(_ taskId: UUID, result: String) {
        lock.lock()
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].status = .completed
            tasks[idx].result = result
        }
        handles[taskId] = nil
        lock.unlock()
    }
}
