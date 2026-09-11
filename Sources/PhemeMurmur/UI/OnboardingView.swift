import SwiftUI

/// Immersive single-column onboarding: generous whitespace, star dust, a mini
/// nebula core, progress dots and one primary button.
struct OnboardingView: View {

    let onFinish: () -> Void

    @ObservedObject var store: SettingsStore
    @State private var page: OnboardingPage = .welcome
    @State private var permissions: [PermissionItem] = PermissionStatus.current()
    @State private var didRecordOnce = false

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var canAdvance: Bool {
        OnboardingFlow.canAdvance(from: page,
                                  permissions: permissions,
                                  providerType: store.activeProviderType,
                                  apiKey: store.apiKey,
                                  didRecordOnce: didRecordOnce)
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            NebulaHUDView(phase: .transcribing(provider: ""),
                          levels: Array(repeating: 0, count: 15),
                          showsCapsule: false)
                .scaleEffect(0.55)
                .frame(height: 100)

            Text(page.kicker)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))

            Text(page.title)
                .font(.system(size: page == .welcome ? 26 : 22, weight: .semibold))
                .foregroundStyle(.white)

            Text(page.body)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                .frame(maxWidth: 420)

            pageContent

            Spacer()

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(OnboardingPage.allCases, id: \.self) { p in
                        Circle()
                            .fill(p == page
                                  ? DeepSpace.color(DeepSpace.auroraCyan)
                                  : DeepSpace.color(DeepSpace.starDust, opacity: 0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                Button(page == .tryIt ? "完成" : "繼續") { advance() }
                    .disabled(!canAdvance)
                    .buttonStyle(.borderedProminent)
                    .tint(DeepSpace.color(DeepSpace.auroraCyan))
            }
            .padding(.bottom, 6)
        }
        .padding(32)
        .frame(width: 620, height: 520)
        .background(
            RadialGradient(
                colors: [DeepSpace.color(DeepSpace.spaceVoidTop),
                         DeepSpace.color(DeepSpace.spaceVoidBottom)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 10, endRadius: 676
            )
        )
        .preferredColorScheme(.dark)
        .onReceive(pollTimer) { _ in
            permissions = PermissionStatus.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phemeDidTranscribeOnce)) { _ in
            // Only a recording completed while actually on the tryIt page
            // counts — a recording finishing on an earlier page (e.g. because
            // the user pressed the hotkey before reaching tryIt) must not
            // pre-satisfy this page's gate.
            if page == .tryIt { didRecordOnce = true }
        }
        .onChange(of: page) { newPage in
            if newPage == .tryIt {
                NotificationCenter.default.post(name: .phemeOnboardingReachedTryIt, object: nil)
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome, .tryIt:
            EmptyView()
        case .permissions:
            VStack(spacing: 8) {
                ForEach(permissions, id: \.kind) { item in
                    Button {
                        if !item.granted { PermissionStatus.openSettings(for: item.kind) }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.granted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.granted
                                                 ? DeepSpace.color(DeepSpace.auroraCyan)
                                                 : DeepSpace.color(DeepSpace.starDust, opacity: 0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.kind.title).font(.system(size: 14))
                                Text(item.granted ? "已授權" : item.kind.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
        case .provider:
            VStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { store.activeProvider },
                    set: { store.selectProvider($0) }
                )) {
                    // Providers this macOS version cannot run are left out
                    // rather than offered as a dead choice; the settings window
                    // lists them explicitly as unavailable.
                    ForEach(store.providerOptions.filter(\.isAvailable), id: \.name) {
                        Text($0.name).tag($0.name)
                    }
                }
                .pickerStyle(.segmented)
                switch OnboardingFlow.providerPrompt(providerType: store.activeProviderType) {
                case .apiKeyField:
                    SecureField("API Key", text: $store.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                        .onSubmit { store.saveAPIKey() }
                case .noKeyNeeded:
                    Text("不需要 API Key，直接繼續即可。")
                        .font(.system(size: 13.5))
                        .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                case .noUsableProvider:
                    VStack(spacing: 6) {
                        Text("這台 Mac 上沒有可以使用的轉錄服務：Apple 裝置端辨識需要 macOS 26，設定檔裡也沒有任何雲端供應商。")
                            .font(.system(size: 13.5))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .foregroundStyle(DeepSpace.color(DeepSpace.nebulaPink))
                        Text("請先在設定檔加入 OpenAI 或 Gemini 供應商，再重新開啟 PhemeMurmur：\n\(Config.configPath)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                    }
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private func advance() {
        if page == .provider, store.activeProviderNeedsAPIKey { store.saveAPIKey() }
        if let next = OnboardingFlow.next(after: page) {
            page = next
        } else {
            onFinish()
        }
    }
}
