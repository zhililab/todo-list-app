import Foundation
import Combine

@MainActor
final class TrialManager: ObservableObject {
    private let firstLaunchKey = "todo_app_trial_start_date"
    private let daySeconds = 86400.0
    private let trialDays = 7

    let defaults: UserDefaults
    let now: () -> Date

    @Published private(set) var trialState: TrialState = .free

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        refreshTrialState()
    }

    func resetTrial(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: firstLaunchKey)
        refreshTrialState()
    }

    var isTrialActive: Bool {
        if case .trial = trialState { true } else { false }
    }

    var remainingDays: Int {
        if case let .trial(remainingDays) = trialState {
            return remainingDays
        }
        return 0
    }

    func refreshTrialState() {
        let start = defaults.double(forKey: firstLaunchKey)
        if start == 0 {
            defaults.set(now().timeIntervalSince1970, forKey: firstLaunchKey)
            trialState = .trial(remainingDays: trialDays)
            return
        }

        let elapsedDays = Int(floor((now().timeIntervalSince1970 - start) / daySeconds))
        let left = max(trialDays - elapsedDays, 0)
        if left > 0 {
            trialState = .trial(remainingDays: left)
        } else {
            trialState = .free
        }
    }
}
