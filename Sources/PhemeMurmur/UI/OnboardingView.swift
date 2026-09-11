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
                                  hasAPIKey: !store.apiKey.isEmpty,
                                  didRecordOnce: didRecordOnce)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            NebulaHUDView(phase: .transcribing(provider: ""),
                          levels: Array(repeating: 0, count: 15),
                          showsCapsule: false)
                .scaleEffect(0.45)
                .frame(height: 80)

            Text(page.kicker)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))

            Text(page.title)
                .font(.system(size: page == .welcome ? 20 : 17, weight: .semibold))
                .foregroundStyle(.white)

            Text(page.body)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                .frame(maxWidth: 320)

            pageContent

            Spacer()

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(OnboardingPage.allCases, id: \.self) { p in
                        Circle()
                            .fill(p == page
                                  ? DeepSpace.color(DeepSpace.auroraCyan)
                                  : DeepSpace.color(DeepSpace.starDust, opacity: 0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                Button(page == .tryIt ? "完成" : "繼續") { advance() }
                    .disabled(!canAdvance)
                    .buttonStyle(.borderedProminent)
                    .tint(DeepSpace.color(DeepSpace.auroraCyan))
            }
            .padding(.bottom, 6)
        }
        .padding(26)
        .frame(width: 480, height: 400)
        .background(
            RadialGradient(
                colors: [DeepSpace.color(DeepSpace.spaceVoidTop),
                         DeepSpace.color(DeepSpace.spaceVoidBottom)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 10, endRadius: 520
            )
        )
        .preferredColorScheme(.dark)
        .onReceive(pollTimer) { _ in
            permissions = PermissionStatus.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: .phemeDidTranscribeOnce)) { _ in
            didRecordOnce = true
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
                                Text(item.kind.title).font(.system(size: 11.5))
                                Text(item.granted ? "已授權" : item.kind.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
                            }
                            Spacer()
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 320)
        case .provider:
            VStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { store.activeProvider },
                    set: { store.selectProvider($0) }
                )) {
                    ForEach(store.providerNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                SecureField("API Key", text: $store.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06)))
                    .onSubmit { store.saveAPIKey() }
            }
            .frame(maxWidth: 320)
        }
    }

    private func advance() {
        if page == .provider { store.saveAPIKey() }
        if let next = OnboardingFlow.next(after: page) {
            page = next
        } else {
            onFinish()
        }
    }
}
