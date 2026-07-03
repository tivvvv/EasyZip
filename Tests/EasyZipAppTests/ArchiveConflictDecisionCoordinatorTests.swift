import EasyZipCore
import XCTest
@testable import EasyZipApp

@MainActor
final class ArchiveConflictDecisionCoordinatorTests: XCTestCase {
    func testReturnsSubmittedDecision() async throws {
        let promptExpectation = expectation(description: "Shows conflict prompt")
        var presentedPrompt: ArchiveConflictPrompt?
        let coordinator = ArchiveConflictDecisionCoordinator { prompt in
            presentedPrompt = prompt
            promptExpectation.fulfill()
        }
        let resolver = coordinator.makeResolver()
        let conflict = makeConflict(entryPath: "folder/file.txt")

        let decisionTask = Task.detached {
            resolver(conflict)
        }

        await fulfillment(of: [promptExpectation], timeout: 1)
        let prompt = try XCTUnwrap(presentedPrompt)
        coordinator.submitDecision(
            ArchiveConflictDecision(policy: .rename, appliesToRemainingConflicts: false),
            for: prompt.id
        )

        let decision = await decisionTask.value

        XCTAssertEqual(decision, .rename)
    }

    func testAppliesDecisionToRemainingConflicts() async throws {
        let promptExpectation = expectation(description: "Shows first conflict prompt")
        var promptCount = 0
        var presentedPrompt: ArchiveConflictPrompt?
        let coordinator = ArchiveConflictDecisionCoordinator { prompt in
            promptCount += 1
            presentedPrompt = prompt
            promptExpectation.fulfill()
        }
        let resolver = coordinator.makeResolver()

        let firstTask = Task.detached {
            resolver(makeConflict(entryPath: "first.txt"))
        }

        await fulfillment(of: [promptExpectation], timeout: 1)
        let firstPrompt = try XCTUnwrap(presentedPrompt)
        coordinator.submitDecision(
            ArchiveConflictDecision(policy: .overwrite, appliesToRemainingConflicts: true),
            for: firstPrompt.id
        )

        let firstDecision = await firstTask.value
        XCTAssertEqual(firstDecision, .overwrite)

        let secondTask = Task.detached {
            resolver(makeConflict(entryPath: "second.txt"))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        if promptCount > 1, let presentedPrompt {
            coordinator.submitDecision(
                ArchiveConflictDecision(policy: .skip, appliesToRemainingConflicts: false),
                for: presentedPrompt.id
            )
        }

        let secondDecision = await secondTask.value
        XCTAssertEqual(secondDecision, .overwrite)
        XCTAssertEqual(promptCount, 1)
    }

    func testCancelPendingDecisionReturnsSkip() async throws {
        let promptExpectation = expectation(description: "Shows conflict prompt")
        let coordinator = ArchiveConflictDecisionCoordinator { _ in
            promptExpectation.fulfill()
        }
        let resolver = coordinator.makeResolver()

        let decisionTask = Task.detached {
            resolver(makeConflict(entryPath: "cancelled.txt"))
        }

        await fulfillment(of: [promptExpectation], timeout: 1)
        coordinator.cancelPendingDecision()

        let decision = await decisionTask.value

        XCTAssertEqual(decision, .skip)
    }
}

private func makeConflict(entryPath: String) -> ArchiveConflict {
    ArchiveConflict(
        entryPath: entryPath,
        destinationURL: URL(fileURLWithPath: "/tmp/\(entryPath)"),
        existingItemIsDirectory: false,
        incomingItemIsDirectory: false
    )
}
