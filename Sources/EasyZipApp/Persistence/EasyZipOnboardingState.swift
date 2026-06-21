import Foundation

@MainActor
final class EasyZipOnboardingState: ObservableObject {
    static let shared = EasyZipOnboardingState()

    @Published private(set) var firstLaunchGuideCompleted: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        firstLaunchGuideCompleted = userDefaults.bool(forKey: Keys.firstLaunchGuideCompleted)
    }

    var shouldShowFirstLaunchGuide: Bool {
        !firstLaunchGuideCompleted
    }

    func completeFirstLaunchGuide() {
        guard !firstLaunchGuideCompleted else {
            return
        }

        firstLaunchGuideCompleted = true
        userDefaults.set(true, forKey: Keys.firstLaunchGuideCompleted)
    }
}

private enum Keys {
    static let firstLaunchGuideCompleted = "easyzip.onboarding.firstLaunchGuideCompleted"
}
