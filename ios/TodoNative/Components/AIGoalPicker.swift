import Foundation
import SwiftUI

struct AIGoalPickerCandidate: Identifiable, Equatable {
    let id: UUID
    let title: String
    let context: String
    let acceptanceCriteria: String
    let nextPrompt: String
    let sourceGoal: String
    let taskType: TaskType
    let priority: Int
    let status: TodoStatus
    let dueDate: Date?
    let updatedAt: Date

    init?(item: TodoItem) {
        guard let title = AISelectedGoalEligibility.eligibleTitle(for: item) else { return nil }

        id = item.id
        self.title = title
        context = item.context
        acceptanceCriteria = item.acceptanceCriteria
        nextPrompt = item.nextPrompt
        sourceGoal = item.sourceGoal
        taskType = item.taskType
        priority = item.priority
        status = item.status
        dueDate = item.dueDate
        updatedAt = item.updatedAt
    }
}

struct AIGoalPickerPresentation: Equatable {
    let doing: [AIGoalPickerCandidate]
    let todo: [AIGoalPickerCandidate]

    var all: [AIGoalPickerCandidate] {
        doing + todo
    }

    init(items: [TodoItem], query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = items
            .compactMap(AIGoalPickerCandidate.init)
            .filter { candidate in
                guard !normalizedQuery.isEmpty else { return true }
                return [
                    candidate.title,
                    candidate.context,
                    candidate.acceptanceCriteria,
                    candidate.nextPrompt,
                    candidate.sourceGoal
                ]
                .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
            }
            .sorted(by: Self.isOrderedBefore)

        doing = candidates.filter { $0.status == .doing }
        todo = candidates.filter { $0.status == .todo }
    }

    static func candidateRevision(items: [TodoItem]) -> String {
        items
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { item in
                [
                    item.id.uuidString,
                    item.statusRaw,
                    item.isArchived ? "1" : "0",
                    String(item.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
                ]
                .joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func isOrderedBefore(
        _ lhs: AIGoalPickerCandidate,
        _ rhs: AIGoalPickerCandidate
    ) -> Bool {
        let lhsStatusRank = lhs.status == .doing ? 0 : 1
        let rhsStatusRank = rhs.status == .doing ? 0 : 1
        if lhsStatusRank != rhsStatusRank { return lhsStatusRank < rhsStatusRank }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }

        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct AIGoalPicker: View {
    let items: [TodoItem]
    let selectedGoalTaskID: UUID?
    let onSelect: (AIGoalPickerCandidate) -> Void
    let onDirectInput: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""

    private var presentation: AIGoalPickerPresentation {
        AIGoalPickerPresentation(items: items, query: query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onDirectInput()
                        dismiss()
                    } label: {
                        Label(
                            Localization.t("ai.goalPicker.directInput"),
                            systemImage: "square.and.pencil"
                        )
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(Color.accentBlue)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel(Localization.t("ai.goalPicker.directInput"))
                }

                candidateSection(
                    titleKey: "ai.goalPicker.doing",
                    candidates: presentation.doing
                )
                candidateSection(
                    titleKey: "ai.goalPicker.todo",
                    candidates: presentation.todo
                )

                if presentation.all.isEmpty {
                    Text(Localization.t("ai.goalPicker.empty"))
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(Color.appMuted)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.appCardBg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBg)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(Localization.t("ai.goalPicker.searchPlaceholder"))
            )
            .navigationTitle(Localization.t("ai.goalPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.t("common.done")) {
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .appBg()
    }

    @ViewBuilder
    private func candidateSection(
        titleKey: String,
        candidates: [AIGoalPickerCandidate]
    ) -> some View {
        if !candidates.isEmpty {
            Section(Localization.t(titleKey)) {
                ForEach(candidates) { candidate in
                    candidateRow(candidate)
                }
            }
        }
    }

    private func candidateRow(_ candidate: AIGoalPickerCandidate) -> some View {
        let isSelected = selectedGoalTaskID == candidate.id
        let metadata = metadataValues(for: candidate)
        return Button {
            onSelect(candidate)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(candidate.title)
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(Color.appText)
                        .fixedSize(horizontal: false, vertical: true)

                    if dynamicTypeSize.isAccessibilitySize {
                        candidateMetadata(metadata)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                candidateMetadata(metadata)
                            }
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                candidateMetadata(metadata)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(
            [
                metadata.joined(separator: ", "),
                isSelected ? Localization.t("ai.goalPicker.selectionStatus") : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    @ViewBuilder
    private func candidateMetadata(_ metadata: [String]) -> some View {
        ForEach(metadata, id: \.self) { value in
            Text(value)
        }
    }

    private func metadataValues(for candidate: AIGoalPickerCandidate) -> [String] {
        var metadata = [
            candidate.taskType.localizedName,
            Localization.t("ai.goalPicker.priority", candidate.priority)
        ]
        if let dueDate = candidate.dueDate {
            metadata.append(Localization.t("ai.goalPicker.dueDate", localizedDate(dueDate)))
        }
        return metadata
    }

    private func localizedDate(_ date: Date) -> String {
        let localeIdentifier = Localization.currentLanguage == "zh" ? "zh_Hans_CN" : "en_US"
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: localeIdentifier))
        )
    }
}

struct AISelectedGoalSummary: View {
    let candidate: AIGoalPickerCandidate
    let onChange: () -> Void
    let onClear: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Localization.t("ai.goalPicker.selectedTask"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
                Text(candidate.title)
                    .font(AppTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Localization.t("ai.goalPicker.selectionStatus"))

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppTheme.Spacing.xs) {
                    changeButton
                    clearButton
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        changeButton
                        clearButton
                    }
                    VStack(spacing: AppTheme.Spacing.xs) {
                        changeButton
                        clearButton
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBg, in: RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private var changeButton: some View {
        Button(Localization.t("ai.goalPicker.change"), action: onChange)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel(Localization.t("ai.goalPicker.change"))
    }

    private var clearButton: some View {
        Button(Localization.t("ai.goalPicker.clear"), action: onClear)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel(Localization.t("ai.goalPicker.clear"))
    }
}
