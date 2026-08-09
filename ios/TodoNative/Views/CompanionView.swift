import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @StateObject private var buddy = CompanionViewModel()

    var body: some View {
        let _ = lang.language
        NavigationStack {
            VStack(spacing: 0) {
                if buddy.messages.isEmpty {
                    Text(Localization.t("buddy.noMemory"))
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(Color.appMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(buddy.messages) { message in
                                    messageBubble(message)
                                }
                            }
                            .padding(AppTheme.Spacing.md)
                        }
                        .onChange(of: buddy.messages.count) {
                            if let last = buddy.messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                inputBar
            }
            .navigationTitle(Localization.t("tab.companion"))
            .onAppear {
                buddy.greetingIfNeeded(language: Localization.currentLanguage)
                buddy.runMoments(items: vm.unarchivedItems)
            }
        }
        .appBg()
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TextField(Localization.t("buddy.placeholder"), text: $buddy.input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.appCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                        .stroke(Color.appLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
                .accessibilityLabel(Localization.t("buddy.placeholder"))

            Button {
                Task {
                    await buddy.send(items: vm.unarchivedItems, health: vm.healthScore, language: lang.language)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(buddy.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || buddy.isBusy ? Color.appLine : Color.brand)
            }
            .disabled(buddy.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || buddy.isBusy)
            .accessibilityLabel(Localization.t("buddy.send"))
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(Color.appSidebarBg)
    }

    @ViewBuilder
    private func messageBubble(_ message: CompanionViewModel.BuddyMessage) -> some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Color.buddyUserBubble : Color.buddyBuddyBubble
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                        .stroke(isUser ? .clear : Color.buddyBubbleLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
                .frame(maxWidth: isUser ? 320 : 380, alignment: isUser ? .trailing : .leading)

            if !message.actions.isEmpty {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(message.actions) { action in
                        Button(action.label) {
                            buddy.apply(action: action, in: vm)
                        }
                        .ghostButton()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .id(message.id)
    }
}