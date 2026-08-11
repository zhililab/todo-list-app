import SwiftUI
import UIKit

struct CompanionView: View {
    @EnvironmentObject private var vm: TodoViewModel
    @EnvironmentObject private var lang: LanguageEnvironment
    @EnvironmentObject private var consentManager: AIConsentManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var buddy = CompanionViewModel()
    @StateObject private var voice = CompanionVoiceRecorder()
    @State private var composer = CompanionComposerState()
    @State private var voiceError: CompanionVoiceError?
    @FocusState private var composerFocused: Bool

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
            .onDisappear { cancelVoiceInput() }
            .onChange(of: scenePhase) {
                if scenePhase != .active { cancelVoiceInput() }
            }
            .onChange(of: consentManager.resolution) {
                let resolution = consentManager.resolution
                Task {
                    _ = await buddy.resolvePendingConsent(resolution)
                }
            }
        }
        .appBg()
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            inputModeButton

            if composer.mode == .keyboard {
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
                    .focused($composerFocused)
                    .accessibilityLabel(Localization.t("buddy.placeholder"))
                    .accessibilityIdentifier("companion.composer")

                Button {
                    Task {
                        await buddy.send(items: vm.unarchivedItems, health: vm.healthScore, language: lang.language)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(buddy.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || buddy.isBusy ? Color.appLine : Color.brand)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .disabled(buddy.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || buddy.isBusy)
                .accessibilityLabel(Localization.t("buddy.send"))
                .accessibilityIdentifier("companion.send")
            } else {
                voiceRecordButton
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(Color.appSidebarBg)
        .alert(Localization.t("voice.errorTitle"), isPresented: Binding(get: { voiceError != nil }, set: { if !$0 { voiceError = nil } })) {
            Button(Localization.t("common.ok"), role: .cancel) {}
            if voiceErrorNeedsSettings {
                Button(Localization.t("voice.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(voiceError?.localizedDescription ?? Localization.t("voice.recognitionFailed"))
        }
    }

    private var inputModeButton: some View {
        Button {
            if composer.mode == .keyboard {
                composer.switchToVoice()
                composerFocused = false
            } else {
                cancelVoiceInput()
            }
        } label: {
            Image(systemName: composer.mode == .keyboard ? "waveform" : "keyboard")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.appText)
                .frame(width: 44, height: 44)
                .background(Color.appCardBg)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(inputModeAccessibilityLabel)
        .accessibilityIdentifier("companion.inputModeToggle")
    }

    private var inputModeAccessibilityLabel: String {
        if composer.mode == .keyboard {
            return Localization.t("voice.switchToVoice")
        }
        return Localization.t(voice.state == .idle ? "voice.switchToKeyboard" : "voice.cancelAndSwitchToKeyboard")
    }

    private var voiceRecordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                switch voice.state {
                case .requestingPermission, .finalizing:
                    ProgressView()
                case .recording:
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(Color.red)
                case .idle:
                    Image(systemName: "mic.fill")
                        .foregroundStyle(Color.brand)
                }
                Text(voiceButtonText)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.appCardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Spacing.radiusLg, style: .continuous).stroke(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(
            voice.state == .requestingPermission
                || voice.state == .finalizing
                || (voice.state == .idle && buddy.isBusy)
        )
        .accessibilityLabel(voiceActionAccessibilityLabel)
        .accessibilityValue(voice.transcript.isEmpty ? "" : voice.transcript)
        .accessibilityIdentifier("companion.voiceRecord")
    }

    private var voiceButtonText: String {
        switch voice.state {
        case .idle:
            return Localization.t("voice.startRecording")
        case .requestingPermission:
            return Localization.t("voice.requestingPermission")
        case .recording:
            return voice.transcript.isEmpty ? Localization.t("voice.recording") : voice.transcript
        case .finalizing:
            return Localization.t("voice.finalizing")
        }
    }

    private var voiceActionAccessibilityLabel: String {
        switch voice.state {
        case .idle:
            return Localization.t("voice.startRecording")
        case .requestingPermission:
            return Localization.t("voice.requestingPermission")
        case .recording:
            return Localization.t("voice.stopRecording")
        case .finalizing:
            return Localization.t("voice.finalizing")
        }
    }

    private var voiceErrorNeedsSettings: Bool {
        voiceError == .speechPermissionDenied || voiceError == .microphonePermissionDenied
    }

    private func toggleRecording() async {
        if voice.isRecording {
            voice.stop()
            return
        }
        guard !buddy.isBusy else { return }
        composer.beginRecording(currentDraft: buddy.input)
        await voice.start(
            onPartial: { _ in },
            onFinal: { transcript in
                buddy.input = composer.finishRecording(transcript: transcript)
                composerFocused = false
                UIAccessibility.post(
                    notification: .announcement,
                    argument: Localization.t("voice.transcriptReady")
                )
            },
            onError: { error in
                _ = composer.cancelRecording()
                voiceError = error
            }
        )
    }

    private func cancelVoiceInput() {
        if voice.state != .idle {
            voice.cancel()
            if let draft = composer.cancelRecording() {
                buddy.input = draft
            }
        } else {
            composer.switchToKeyboard()
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
