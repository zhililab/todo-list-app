import Foundation

@MainActor
final class LanguageEnvironment: ObservableObject {
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: Localization.languageKey)
        }
    }

    init() {
        language = Localization.currentLanguage
    }

    static nonisolated func setDefaultLanguage() {
        UserDefaults.standard.removeObject(forKey: Localization.languageKey)
    }

    func setLanguage(_ language: String) {
        self.language = language
    }
}
