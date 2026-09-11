import SwiftUI

/// The Mark III boot sequence: an armour plate with a reactor warming up at the
/// top, telemetry headers, and one lit CTA per step.
struct OnboardingView: View {

    let onFinish: () -> Void

    @ObservedObject var store: SettingsStore
    @State private var page: OnboardingPage = .welcome
    @State private var permissions: [PermissionItem] = PermissionStatus.current()
    @State private var didRecordOnce = false

    static let windowSize = CGSize(width: 620, height: 520)

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var canAdvance: Bool {
        OnboardingFlow.canAdvance(from: page,
                                  permissions: permissions,
                                  providerType: store.activeProviderType,
                                  apiKey: store.apiKey,
                                  didRecordOnce: didRecordOnce)
    }

    var body: some View {
        ZStack {
            MarkIII.bootBackdrop(diagonal: 700)
            content
            ScanlineOverlay(showsSweep: false, lineOpacity: 0.03)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .clipShape(Chamfer(cut: 20))
        .overlay(Chamfer(cut: 20).strokeBorder(MarkIII.plateEdge, lineWidth: 1))
        .preferredColorScheme(.dark)
        .onReceive(pollTimer) { _ in
            permissions = PermissionStatus.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phemeDidTranscribeOnce)) { _ in
            // Only a recording completed while actually on the tryIt page
            // counts — a recording finishing on an earlier page must not
            // pre-satisfy this page's gate.
            if page == .tryIt { didRecordOnce = true }
        }
        .onChange(of: page) { newPage in
            if newPage == .tryIt {
                NotificationCenter.default.post(name: .phemeOnboardingReachedTryIt, object: nil)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            HStack {
                MonoText(page.kicker, size: 10, tracking: 1.8,
                         color: MarkIII.gold, opacity: 0.7)
                Spacer()
                MonoText("INITIALISING", size: 10, tracking: 1.8,
                         color: MarkIII.gold, opacity: 0.7)
            }

            Spacer(minLength: 0)

            bootCore

            Text(page.title)
                .font(MarkIII.font(page.titleSize, .bold))
                .kerning(1)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(MarkIII.font(14))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundStyle(MarkIII.color(MarkIII.dim))
                .frame(maxWidth: 430)

            pageContent

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                BootPips(total: OnboardingPage.allCases.count, current: page.rawValue)
                Spacer()
                Button(page.ctaTitle) { advance() }
                    .buttonStyle(BootCTAStyle())
                    .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
    }

    /// The reactor is large and centre stage on the opening page, then shrinks
    /// to a header ornament once the user is working through the steps.
    private var bootCore: some View {
        let scale: CGFloat = page == .welcome ? 0.72 : 0.38
        return ReactorCluster(tint: MarkIII.gold,
                              ring: MarkIII.gold,
                              levels: Array(repeating: 0.12, count: 15),
                              speed: 5,
                              pulses: page == .welcome)
            .scaleEffect(scale)
            .frame(width: ReactorCluster.systemSize * scale,
                   height: ReactorCluster.systemSize * scale)
            .animation(.easeInOut(duration: 0.35), value: page)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome, .tryIt:
            if page == .tryIt { hotkeyBadge }
        case .permissions:
            permissionList
        case .provider:
            providerPicker
        }
    }

    /// The calibration prompt: a pulsing hot bead next to the key to press.
    private var hotkeyBadge: some View {
        StatusChip(border: MarkIII.gold, borderOpacity: 0.35,
                   fill: MarkIII.crimson, fillOpacity: 0.16) {
            HStack(spacing: 10) {
                PulsingBead(color: MarkIII.hot)
                MonoText("HOLD \(store.hotkey.shortName.uppercased())",
                         size: 13, weight: .semibold, tracking: 1.6,
                         color: MarkIII.goldBright)
            }
        }
    }

    private var permissionList: some View {
        VStack(spacing: 9) {
            ForEach(permissions, id: \.kind) { item in
                Button {
                    if !item.granted { PermissionStatus.openSettings(for: item.kind) }
                } label: {
                    ChamferRow(isActive: item.granted) {
                        HStack(spacing: 12) {
                            Diamond(color: MarkIII.goldBright, side: 10,
                                    filled: item.granted, glows: item.granted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.kind.title)
                                    .font(MarkIII.font(15, .semibold))
                                    .foregroundStyle(.white)
                                MonoText(item.granted ? "GRANTED" : item.kind.detail,
                                         size: 11, weight: .regular, tracking: 0,
                                         color: item.granted ? MarkIII.ink : MarkIII.dim,
                                         opacity: item.granted ? 0.8 : 1)
                            }
                            Spacer(minLength: 0)
                            MonoText(item.granted ? "✔" : "開啟設定",
                                     size: 10, weight: .bold, tracking: 1.4,
                                     color: item.granted ? MarkIII.goldBright : MarkIII.hot)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 430)
    }

    private var providerPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                // Providers this macOS version cannot run are left out rather
                // than offered as a dead choice; the settings console lists them
                // explicitly as unavailable.
                ForEach(store.providerOptions.filter(\.isAvailable), id: \.name) { option in
                    let selected = option.name == store.activeProvider
                    Button { store.selectProvider(option.name) } label: {
                        Text(option.name)
                            .font(MarkIII.font(14, .semibold))
                            .foregroundStyle(selected
                                             ? MarkIII.color(MarkIII.onGold)
                                             : MarkIII.color(MarkIII.dim))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                if selected {
                                    MarkIII.goldSlab.clipShape(Chamfer(cut: 8))
                                } else {
                                    MarkIII.color(MarkIII.gold, opacity: 0.08)
                                        .clipShape(Chamfer(cut: 8))
                                }
                            }
                            .overlay {
                                if !selected {
                                    Chamfer(cut: 8).strokeBorder(
                                        MarkIII.color(MarkIII.gold, opacity: 0.28), lineWidth: 1)
                                }
                            }
                            .shadow(color: MarkIII.color(MarkIII.gold,
                                                         opacity: selected ? 0.3 : 0), radius: 10)
                    }
                    .buttonStyle(.plain)
                }
            }

            switch OnboardingFlow.providerPrompt(providerType: store.activeProviderType) {
            case .apiKeyField:
                ChamferRow {
                    SecureField("API Key", text: $store.apiKey)
                        .textFieldStyle(.plain)
                        .font(MarkIII.mono(13))
                        .kerning(1)
                        .foregroundStyle(MarkIII.color(MarkIII.goldBright))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .onSubmit { store.saveAPIKey() }
                }
            case .noKeyNeeded:
                Text("不需要 API Key，直接繼續即可。")
                    .font(MarkIII.font(13.5))
                    .foregroundStyle(MarkIII.color(MarkIII.dim))
            case .noUsableProvider:
                VStack(spacing: 6) {
                    Text("這台 Mac 上沒有可以使用的轉錄服務：Apple 裝置端辨識需要 macOS 26，設定檔裡也沒有任何雲端供應商。")
                        .font(MarkIII.font(13.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .foregroundStyle(MarkIII.color(MarkIII.hot))
                    Text("請先在設定檔加入 OpenAI 或 Gemini 供應商，再重新開啟 PhemeMurmur：\n\(Config.configPath)")
                        .font(MarkIII.mono(11.5))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MarkIII.color(MarkIII.dim))
                }
            }
        }
        .frame(width: 430)
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

/// A small glowing dot that breathes — used wherever the design wants to say
/// "waiting for you".
struct PulsingBead: View {
    var color: MarkIII.RGB
    var size: CGFloat = 7

    @State private var lit = false

    var body: some View {
        Circle()
            .fill(MarkIII.color(color))
            .frame(width: size, height: size)
            .shadow(color: MarkIII.color(color), radius: 5)
            .scaleEffect(lit ? 1.07 : 0.93)
            .opacity(lit ? 1 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}
