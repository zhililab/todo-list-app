import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var buddy = CompanionViewModel()
    @StateObject private var voice = CompanionVoiceRecorder()
    @State private var voiceError: String?

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
                                if buddy.isTyping {
                                    typingIndicator
                                        .transition(.opacity)
                                }
                            }
                            .padding(AppTheme.Spacing.md)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: buddy.messages.count)
                        }
                        .onChange(of: buddy.messages.count) {
                            if let last = buddy.messages.last {
                                if reduceMotion {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                } else {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
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
            micButton

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
        .alert(Localization.t("voice.micPermissionDenied"), isPresented: Binding(get: { voiceError != nil }, set: { if !$0 { voiceError = nil } })) {
            Button(Localization.t("common.ok"), role: .cancel) {}
        } message: {
            Text(voiceError ?? "")
        }
    }

    // iMessage 风格麦克风按钮：点击开始/结束录音，实时填入输入框
    private var micButton: some View {
        Button {
            Task {
                await toggleRecording()
            }
        } label: {
            Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(voice.isRecording ? Color.red : Color.brand)
        }
        .buttonStyle(.plain)
        .disabled(buddy.isBusy)
        .accessibilityLabel(Localization.t(voice.isRecording ? "voice.stopRecording" : "voice.micA11y"))
    }

    private func toggleRecording() async {
        if voice.isRecording {
            voice.stop()
            return
        }
        do {
            try await voice.start { [weak buddy] transcript in
                guard let buddy else { return }
                if !transcript.isEmpty {
                    buddy.input = transcript
                }
            }
        } catch {
            voiceError = error.localizedDescription
        }
    }

    // iMessage 风格气泡：用户右对齐蓝渐变 + 尾巴；伙伴左对齐浅底 + 尾巴
    @ViewBuilder
    private func messageBubble(_ message: CompanionViewModel.BuddyMessage) -> some View {
        let isUser = message.role == "user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(isUser ? Color.white : Color.appText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x5A9BF8), Color(hex: 0x3D7EF0)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.buddyBuddyBubble)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg)
                        .stroke(isUser ? .clear : Color.buddyBubbleLine, lineWidth: 1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppTheme.Spacing.radiusLg,
                        style: .continuous
                    )
                    .clipToBubbleTail(isUser: isUser)
                )
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
        .transition(
            isUser
                ? .asymmetric(insertion: .scale(scale: 0.88).combined(with: .opacity), removal: .opacity)
                : .asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                    removal: .opacity
                )
        )
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.appMuted.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(typingPulse ? 1.0 : 0.5)
                    .animation(
                        typingPulse
                            ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.18)
                            : .default,
                        value: typingPulse
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.buddyBuddyBubble)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.xs)
        .onAppear {
            if !reduceMotion {
                typingPulse = true
            }
        }
    }

    @State private var typingPulse = false
}

private extension RoundedRectangle {
    func clipToBubbleTail(isUser: Bool) -> some Shape {
        BubbleTailShape(cornerRadius: AppTheme.Spacing.radiusLg, isUser: isUser)
    }
}

// 简单的 iMessage 气泡尾巴：用户消息尾巴在右下，伙伴在左下
private struct BubbleTailShape: Shape {
    let cornerRadius: CGFloat
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        var path = Path()
        let tail: CGFloat = 8
        if isUser {
            // 右下尾巴
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
            path.move(to: CGPoint(x: rect.maxX - 20, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY + tail))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY))
            path.closeSubpath()
        } else {
            // 左下尾巴
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
            path.move(to: CGPoint(x: rect.minX + 20, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY + tail))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}