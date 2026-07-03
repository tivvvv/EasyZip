import XCTest
@testable import EasyZipApp

final class ArchiveQueuedTaskTests: XCTestCase {
    func testStatusRetryAndFinishedSemantics() {
        XCTAssertTrue(ArchiveQueuedTaskStatus.failed.allowsRetry)
        XCTAssertTrue(ArchiveQueuedTaskStatus.cancelled.allowsRetry)
        XCTAssertFalse(ArchiveQueuedTaskStatus.running.allowsRetry)
        XCTAssertFalse(ArchiveQueuedTaskStatus.waiting.allowsRetry)
        XCTAssertFalse(ArchiveQueuedTaskStatus.succeeded.allowsRetry)

        XCTAssertTrue(ArchiveQueuedTaskStatus.running.allowsCancel)
        XCTAssertTrue(ArchiveQueuedTaskStatus.waiting.allowsCancel)
        XCTAssertFalse(ArchiveQueuedTaskStatus.succeeded.allowsCancel)
        XCTAssertFalse(ArchiveQueuedTaskStatus.failed.allowsCancel)
        XCTAssertFalse(ArchiveQueuedTaskStatus.cancelled.allowsCancel)

        XCTAssertTrue(ArchiveQueuedTaskStatus.succeeded.isFinished)
        XCTAssertTrue(ArchiveQueuedTaskStatus.failed.isFinished)
        XCTAssertTrue(ArchiveQueuedTaskStatus.cancelled.isFinished)
        XCTAssertFalse(ArchiveQueuedTaskStatus.running.isFinished)
        XCTAssertFalse(ArchiveQueuedTaskStatus.waiting.isFinished)
    }
}
