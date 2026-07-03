import EasyZipCore
import Foundation

struct ArchiveConflictPrompt: Identifiable, Sendable {
    let id: UUID
    let conflict: ArchiveConflict

    init(id: UUID = UUID(), conflict: ArchiveConflict) {
        self.id = id
        self.conflict = conflict
    }

    var entryPath: String {
        conflict.entryPath
    }

    var destinationPath: String {
        conflict.destinationURL.path
    }

    var existingKindText: String {
        conflict.existingItemIsDirectory ? "现有项目是文件夹" : "现有项目是文件"
    }

    var existingKindIconName: String {
        conflict.existingItemIsDirectory ? "folder" : "doc"
    }

    var incomingKindText: String {
        conflict.incomingItemIsDirectory ? "归档条目是文件夹" : "归档条目是文件"
    }

    var incomingKindIconName: String {
        conflict.incomingItemIsDirectory ? "folder" : "archivebox"
    }
}

struct ArchiveConflictDecision: Sendable {
    let policy: OverwritePolicy
    let appliesToRemainingConflicts: Bool
}

final class ArchiveConflictDecisionCoordinator: @unchecked Sendable {
    typealias PromptPresenter = @MainActor @Sendable (ArchiveConflictPrompt) -> Void

    private let presenter: PromptPresenter
    private let lock = NSLock()
    private var remainingDecision: ArchiveConflictDecision?
    private var pendingPromptID: UUID?
    private var pendingSemaphore: DispatchSemaphore?
    private var pendingDecision: ArchiveConflictDecision?

    init(presenter: @escaping PromptPresenter) {
        self.presenter = presenter
    }

    func makeResolver() -> ArchiveConflictResolver {
        { [weak self] conflict in
            guard let self else {
                return .skip
            }

            return self.resolve(conflict)
        }
    }

    func submitDecision(_ decision: ArchiveConflictDecision, for promptID: UUID) {
        lock.lock()
        guard pendingPromptID == promptID else {
            lock.unlock()
            return
        }

        pendingDecision = decision
        pendingPromptID = nil
        let semaphore = pendingSemaphore
        pendingSemaphore = nil
        lock.unlock()

        semaphore?.signal()
    }

    func cancelPendingDecision() {
        lock.lock()
        guard let promptID = pendingPromptID else {
            lock.unlock()
            return
        }
        lock.unlock()

        submitDecision(
            ArchiveConflictDecision(policy: .skip, appliesToRemainingConflicts: true),
            for: promptID
        )
    }

    private func resolve(_ conflict: ArchiveConflict) -> OverwritePolicy {
        lock.lock()
        if let remainingDecision {
            lock.unlock()
            return remainingDecision.policy
        }
        lock.unlock()

        guard !Task.isCancelled else {
            return .skip
        }

        let prompt = ArchiveConflictPrompt(conflict: conflict)
        let semaphore = DispatchSemaphore(value: 0)

        lock.lock()
        if Task.isCancelled {
            lock.unlock()
            return .skip
        }
        pendingPromptID = prompt.id
        pendingSemaphore = semaphore
        pendingDecision = nil
        lock.unlock()

        Task { @MainActor in
            guard self.isPendingPrompt(prompt.id) else {
                return
            }

            presenter(prompt)
        }

        semaphore.wait()

        lock.lock()
        let decision = pendingDecision ?? ArchiveConflictDecision(
            policy: .skip,
            appliesToRemainingConflicts: false
        )
        pendingDecision = nil

        if decision.appliesToRemainingConflicts {
            remainingDecision = decision
        }

        lock.unlock()

        return decision.policy
    }

    private func isPendingPrompt(_ promptID: UUID) -> Bool {
        lock.lock()
        let isPending = pendingPromptID == promptID
        lock.unlock()

        return isPending
    }
}
