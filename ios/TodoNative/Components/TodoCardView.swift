import SwiftUI

struct TodoCardView: View {
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flashOpacity: Double = 0

    let item: TodoItem
    let onStatusChange: (TodoStatus) -> Void
    let onArchive: () -> Void
    let onDelete: (() -> Void)?
    let onEdit: (() -> Void)?

    init(
        item: TodoItem,
        onStatusChange: @escaping (TodoStatus) -> Void,
        onArchive: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.item = item
        self.onStatusChange = onStatusChange
        self.onArchive = onArchive
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    private var chipColor: Color {
        switch item.taskType {
        case .personal: return .accentBlue
        case .code: return Color(hex: 0x5092FF)
        case .product: return Color(hex: 0xFF8A3D)
        case .learning: return Color(hex: 0xF2C744)
        case .life: return Color(hex: 0x22A662)
        }
    }

    private var nextActionTitle: String {
        switch item.status {
        case .todo:
            return Localization.t("card.start")
        case .doing:
            return Localization.t("card.complete")
        case .done:
            return Localization.t("card.done")
        case .archived:
            return Localization.t("card.archived")
        }
    }

    private var progressColor: Color {
        switch item.status {
        case .todo:
            return .warning
        case .doing:
            return .accentBlue
        case .done:
            return .success
        case .archived:
            return .secondary
        }
    }

    private var statusText: String {
        switch item.status {
        case .todo: return Localization.t("card.statusTodo")
        case .doing: return Localization.t("card.statusDoing")
        case .done: return Localization.t("card.statusDone")
        case .archived: return Localization.t("card.statusArchived")
        }
    }

    private var nextStatus: TodoStatus {
        switch item.status {
        case .todo: return .doing
        case .doing: return .done
        case .done, .archived: return .done
        }
    }

    var body: some View {
        let _ = lang.language
        HStack(alignment: .top, spacing: 10) {
            // web .task-checkbox
            Button {
                onStatusChange(item.isCompleted ? .doing : .done)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? Color.accentBlue : Color.appLine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? Localization.t("card.unmarkDone") : Localization.t("card.markDone"))
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // web .task-text（完成划线）
                Text(item.title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(item.isCompleted ? Color(hex: 0x8E8883) : Color(hex: 0x32302D))
                    .strikethrough(item.isCompleted, color: Color(hex: 0x8E8883))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    // web 类型胶囊
                    Text(item.taskType.localizedName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(chipColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(chipColor.opacity(0.14)))
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(progressColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(progressColor.opacity(0.14)))
                    Spacer()
                }
                .padding(.top, 3)

                // web .task-meta
                HStack(spacing: 8) {
                    Label("\(item.priority)", systemImage: "flag.fill")
                    Text(Localization.t("card.minutes", item.estimatedMinutes))
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.success)
                .padding(.top, 2)

                // web .task-chips：上下文 / 验收 / 下一步 / 来源
                if !item.context.isEmpty || !item.acceptanceCriteria.isEmpty || !item.nextPrompt.isEmpty || !item.sourceGoal.isEmpty {
                    FlowChips(
                        showContext: !item.context.isEmpty,
                        showAcceptance: !item.acceptanceCriteria.isEmpty,
                        showPrompt: !item.nextPrompt.isEmpty,
                        sourceGoal: item.sourceGoal
                    )
                    .padding(.top, 4)
                }

                // 主操作行：仅保留主动作按钮，其余收纳到滑动/长按菜单
                HStack(spacing: 8) {
                    if !item.isCompleted {
                        Button(nextActionTitle) {
                            onStatusChange(nextStatus)
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.brand)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
                        .buttonStyle(.plain)
                        .accessibilityLabel(Localization.t("card.updateStatusA11y", nextActionTitle))
                    } else {
                        Text(Localization.t("card.done"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.success)
                    }
                    Spacer()
                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.ghostText)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Localization.t("card.editA11y"))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.white)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onStatusChange(nextStatus)
            } label: {
                Label(nextActionTitle, systemImage: "arrow.right.circle")
            }
            Button {
                onArchive()
            } label: {
                Label(Localization.t("card.archive"), systemImage: "archivebox")
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(Localization.t("card.delete"), systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(Localization.t("card.delete"), systemImage: "trash")
                }
            }
            Button {
                onArchive()
            } label: {
                Label(Localization.t("card.archive"), systemImage: "archivebox")
            }
            .tint(.accentBlue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Localization.t("card.a11y", item.title, item.taskType.localizedName, item.priority, statusText, item.estimatedMinutes))
        .accessibilityActions {
            Button(Localization.t("card.archive")) { onArchive() }
            if let onDelete {
                Button(Localization.t("card.delete"), role: .destructive) { onDelete() }
            }
        }
        .onChange(of: item.isCompleted) { _, completed in
            guard completed else { return }
            flashOpacity = 0.35
            withAnimation(AppTheme.Motion.resolvedFade(AppTheme.Motion.stateChange, reduceMotion: reduceMotion)) {
                flashOpacity = 0
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                .fill(Color.accentSoft)
                .opacity(flashOpacity)
        )
    }
}

private struct FlowChips: View {
    @EnvironmentObject private var lang: LanguageEnvironment

    let showContext: Bool
    let showAcceptance: Bool
    let showPrompt: Bool
    let sourceGoal: String

    var body: some View {
        let _ = lang.language
        HStack(spacing: 6) {
            if showContext { Text(Localization.t("card.chipContext")).taskChip() }
            if showAcceptance { Text(Localization.t("card.chipAcceptance")).taskChip() }
            if showPrompt { Text(Localization.t("card.chipPrompt")).taskChip() }
            if !sourceGoal.isEmpty {
                Text(Localization.t("card.chipSource", sourceGoal))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.chipSourceText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.chipSourceBg)
                            .overlay(Capsule().stroke(Color.chipSourceBorder, lineWidth: 1))
                    )
            }
        }
    }
}
