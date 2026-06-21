import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipOnboardingStateTests: XCTestCase {
    func testShowsFirstLaunchGuideWhenStorageIsEmpty() {
        let state = EasyZipOnboardingState(userDefaults: makeUserDefaults())

        XCTAssertFalse(state.firstLaunchGuideCompleted)
        XCTAssertTrue(state.shouldShowFirstLaunchGuide)
    }

    func testPersistsCompletedFirstLaunchGuide() {
        let defaults = makeUserDefaults()
        let state = EasyZipOnboardingState(userDefaults: defaults)

        state.completeFirstLaunchGuide()

        let reloadedState = EasyZipOnboardingState(userDefaults: defaults)
        XCTAssertTrue(reloadedState.firstLaunchGuideCompleted)
        XCTAssertFalse(reloadedState.shouldShowFirstLaunchGuide)
    }

    func testCompletingFirstLaunchGuideIsIdempotent() {
        let state = EasyZipOnboardingState(userDefaults: makeUserDefaults())

        state.completeFirstLaunchGuide()
        state.completeFirstLaunchGuide()

        XCTAssertTrue(state.firstLaunchGuideCompleted)
        XCTAssertFalse(state.shouldShowFirstLaunchGuide)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipOnboardingStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
