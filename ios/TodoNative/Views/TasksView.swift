import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var captureText = ""
    @State private var type: TaskType = .personal
    @State private var showDetails = false
    @State private var context = ""
    @State private var criteria = ""
    @State private var prompt = ""
    @State private var minutes = 15
    @State private var priority = 3

    @State private var showPaywall = false

    @State private var editingItem: TodoItem?

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    private var filteredList: [TodoItem] {
        vm.filteredItems
    }

    var body: some View {
        let _ = lang.language
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.md) {
                        if isWideLayout {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                capturePanel
                                    .frame(maxWidth: .infinity)
                                taskListSection
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            capturePanel
                            taskListSection
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }

                if !purchaseManager.canUsePremiumFeature {
                    FloatingPaywallButton(showPaywall: $showPaywall)
                }
            }
            .navigationTitle(Localization.t("tasks.title"))
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $editingItem) { item in
                TaskEditView(item: item) { title, context, criteria, prompt, minutes, priority, dueDate in
                    vm.updateItem(
                        item,
                        title: title,
                        context: context,
                        criteria: criteria,
                        prompt: prompt,
                        minutes: minutes,
                        priority: priority,
                        dueDate: dueDate
                    )
                }
            }
            .onAppear {
                vm.fetchItems()
            }
        }
        .appBg()
    }

    // web .intent-panel：自然语言输入 + 类型 + 捕捉
    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Localization.t("tasks.inboxTag"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xAB6C57))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(Localization.t("tasks.headline"))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // web .add-row
            TextField(Localization.t("tasks.inputPlaceholder"), text: $captureText, axis: .vertical)
                .font(.system(size: 16, design: .rounded))
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                        .stroke(Color.appLine, lineWidth: 1)
                )
                .accessibilityLabel(Localization.t("tasks.inputA11y"))

            // web .task-meta-row：任务类型选择
            HStack {
                Text(Localization.t("tasks.taskType"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x8E8177))

                Picker(Localization.t("tasks.taskType"), selection: $type) {
                    ForEach(TaskType.allCases) { taskType in
                        Text(taskType.localizedName).tag(taskType)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.appText)

                Spacer()

                Button {
                    capture()
                } label: {
                    Text(Localization.t("tasks.capture"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Color.brand)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm))
                }
                .buttonStyle(.plain)
                .disabled(captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .accessibilityLabel(Localization.t("tasks.captureA11y"))
            }

            // 高级选项：对齐 web Notes 能力（默认折叠）
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(Localization.t("tasks.context"), text: $context)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .rounded))
                    TextField(Localization.t("tasks.acceptance"), text: $criteria)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .rounded))
                    TextField(Localization.t("tasks.prompt"), text: $prompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .rounded))

                    HStack(spacing: 12) {
                        Stepper(Localization.t("tasks.priority", priority), value: $priority, in: 1...5)
                            .font(.system(size: 14, design: .rounded))
                        Stepper(Localization.t("tasks.minutes", minutes), value: $minutes, in: 5...240, step: 5)
                            .font(.system(size: 14, design: .rounded))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(showDetails ? Localization.t("tasks.collapse") : Localization.t("tasks.expand"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.accentBlue)
            }
            .tint(Color.accentBlue)
            .font(.system(size: 14, design: .rounded))
        }
        .padding(AppTheme.Spacing.md)
        .background(
            Color(hex: 0xFFFDFB)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                        .stroke(Color.appLine, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
    }

    private var taskListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(Localization.t("tasks.listTitle"))
                    .font(AppTheme.Typography.headline)
                Spacer()
                if !vm.completedItems.isEmpty {
                    Button(Localization.t("tasks.clearCompleted")) {
                        withAnimation(listAnimation) { vm.clearCompleted() }
                    }
                    .ghostButton()
                    .accessibilityLabel(Localization.t("tasks.clearCompletedA11y"))
                }
                Text(Localization.t("tasks.taskCount", filteredList.count))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(Color.appMuted)
            }

            // 筛选：第一行状态胶囊，第二行类型筛选
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(TaskFilter.allCases) { filter in
                        statusChip(filter)
                    }
                    Spacer()
                }

                HStack {
                    Text(Localization.t("tasks.type"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(hex: 0x8E8177))
                    Picker(Localization.t("tasks.type"), selection: Binding<TaskType?>(
                        get: { vm.selectedType },
                        set: { vm.selectedType = $0 }
                    )) {
                        Text(Localization.t("tasks.allTypes")).tag(nil as TaskType?)
                        ForEach(TaskType.allCases) { taskType in
                            Text(taskType.localizedName).tag(Optional(taskType))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.ghostText)
                    .accessibilityLabel(Localization.t("tasks.typeA11y"))
                    Spacer()
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                    .stroke(Color.appLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))

            if filteredList.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredList, id: \.id) { item in
                        TodoCardView(item: item) { status in
                            withAnimation(listAnimation) { vm.updateStatus(item, status: status) }
                        } onArchive: {
                            withAnimation(listAnimation) { vm.archive(item) }
                        } onDelete: {
                            withAnimation(listAnimation) { vm.delete(item) }
                        } onEdit: {
                            editingItem = item
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.85))
                        ))
                    }
                }
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                        .stroke(Color.appLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
            }
        }
    }

    private func statusChip(_ filter: TaskFilter) -> some View {
        let active = vm.selectedStatusFilter == filter
        return Button {
            vm.selectedStatusFilter = filter
        } label: {
            Text(filter.localizedName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(active ? .white : Color(hex: 0x6A635E))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                        .fill(active ? Color.accentBlue : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusSm)
                        .stroke(active ? Color.clear : Color.appLine, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localization.t("tasks.filterA11y", filter.localizedName))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Localization.t("tasks.emptyTitle"))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appText)
            Text(Localization.t("tasks.emptyHint"))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd)
                .stroke(Color.appLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusMd))
    }

    private func capture() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if showDetails {
            withAnimation(listAnimation) {
                vm.addItem(
                    title: text,
                    type: type,
                    context: context,
                    criteria: criteria,
                    prompt: prompt,
                    minutes: minutes,
                    priority: priority
                )
            }
            context = ""
            criteria = ""
            prompt = ""
        } else {
            withAnimation(listAnimation) { vm.captureNaturalLanguage(text, type: type) }
        }
        captureText = ""
    }
}

private struct FloatingPaywallButton: View {
    @Binding var showPaywall: Bool

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            Label(Localization.t("tasks.upgrade"), systemImage: "crown.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brand)
                .clipShape(Capsule())
                .shadow(color: Color.brand.opacity(0.4), radius: 6, y: 6)
        }
        .padding(.trailing, 18)
        .padding(.bottom, 24)
        .accessibilityLabel(Localization.t("tasks.upgradeA11y"))
    }
}