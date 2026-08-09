import SwiftUI

struct TaskEditView: View {
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var context: String
    @State private var criteria: String
    @State private var prompt: String
    @State private var minutes: Int
    @State private var priority: Int
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool

    let onSave: (String, String, String, String, Int, Int, Date?) -> Void

    init(item: TodoItem, onSave: @escaping (String, String, String, String, Int, Int, Date?) -> Void) {
        _title = State(initialValue: item.title)
        _context = State(initialValue: item.context)
        _criteria = State(initialValue: item.acceptanceCriteria)
        _prompt = State(initialValue: item.nextPrompt)
        _minutes = State(initialValue: item.estimatedMinutes)
        _priority = State(initialValue: item.priority)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date())
        self.onSave = onSave
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let _ = lang.language
        NavigationStack {
            Form {
                Section(Localization.t("edit.titleSection")) {
                    TextField(Localization.t("edit.titlePlaceholder"), text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section(Localization.t("edit.details")) {
                    TextField(Localization.t("tasks.context"), text: $context)
                        .textFieldStyle(.roundedBorder)
                    TextField(Localization.t("tasks.acceptance"), text: $criteria)
                        .textFieldStyle(.roundedBorder)
                    TextField(Localization.t("tasks.prompt"), text: $prompt)
                        .textFieldStyle(.roundedBorder)
                }

                Section(Localization.t("edit.plan")) {
                    Stepper(Localization.t("tasks.priority", priority), value: $priority, in: 1...5)
                    Stepper(Localization.t("tasks.minutes", minutes), value: $minutes, in: 5...240, step: 5)
                }

                Section(Localization.t("tasks.dueDate")) {
                    DatePicker(Localization.t("tasks.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: dueDate) { hasDueDate = true }
                    Button(Localization.t("tasks.clearDue")) {
                        hasDueDate = false
                    }
                    .disabled(!hasDueDate)
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle(Localization.t("edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localization.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localization.t("common.save")) {
                        onSave(trimmedTitle, context, criteria, prompt, minutes, priority, hasDueDate ? dueDate : nil)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }
}
