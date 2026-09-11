import AppKit
import SwiftUI

/// The Mark III control console: a chamfered armour plate split into a channel
/// rail and a detail pane, under scanlines and a slow sweeping band.
struct SettingsView: View {

    @ObservedObject var store: SettingsStore
    @State private var selection: SettingsTab = .transcription

    static let windowSize = CGSize(width: 820, height: 560)

    var body: some View {
        ZStack {
            MarkIII.consoleBackdrop(diagonal: 1000)
            HStack(spacing: 0) {
                rail
                detail
            }
            ScanlineOverlay()
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .clipShape(Chamfer(cut: 20))
        .overlay(Chamfer(cut: 20).strokeBorder(MarkIII.plateEdge, lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            railBadge
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                railItem(tab)
            }
            Spacer(minLength: 0)
            arcOutput
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .frame(width: 198)
        .background(
            LinearGradient(colors: [MarkIII.color(MarkIII.crimson, opacity: 0.10),
                                    MarkIII.color(MarkIII.plateDeep, opacity: 0.6)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MarkIII.color(MarkIII.gold, opacity: 0.22))
                .frame(width: 1)
        }
    }

    /// The rail's masthead: a molten forge bead next to the mark number.
    private var railBadge: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(RadialGradient(
                    colors: [MarkIII.color((1.0, 0.965, 0.878)),
                             MarkIII.color(MarkIII.goldBright),
                             MarkIII.color((1.0, 0.584, 0.133)),
                             MarkIII.color(MarkIII.crimson),
                             MarkIII.color((0.227, 0.039, 0.047))],
                    center: UnitPoint(x: 0.46, y: 0.42),
                    startRadius: 1, endRadius: 12))
                .overlay(Circle().strokeBorder(MarkIII.color(MarkIII.gold, opacity: 0.85),
                                               lineWidth: 1.5))
                .frame(width: 22, height: 22)
                .shadow(color: MarkIII.color((1.0, 0.549, 0.157), opacity: 0.75), radius: 7)
            MonoText("MK III", size: 11, weight: .bold, tracking: 2, color: MarkIII.goldBright)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 16)
    }

    private func railItem(_ tab: SettingsTab) -> some View {
        let selected = selection == tab
        return Button { selection = tab } label: {
            HStack(spacing: 10) {
                Text(tab.glyph)
                    .font(MarkIII.font(13))
                    .frame(width: 18)
                Text(tab.title)
                    .font(MarkIII.font(14, .medium))
                Spacer(minLength: 0)
                Text("▸")
                    .font(MarkIII.mono(10, .bold))
                    .opacity(selected ? 1 : 0)
            }
            .foregroundStyle(selected ? Color.white : MarkIII.color(MarkIII.dim))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                if selected {
                    LinearGradient(colors: [MarkIII.color(MarkIII.crimson, opacity: 0.55),
                                            MarkIII.color(MarkIII.gold, opacity: 0.16)],
                                   startPoint: .leading, endPoint: .trailing)
                    .clipShape(Chamfer(cut: 8))
                    .overlay(Chamfer(cut: 8).strokeBorder(
                        MarkIII.color(MarkIII.goldBright, opacity: 0.55), lineWidth: 1))
                    .shadow(color: MarkIII.color(MarkIII.crimson, opacity: 0.3), radius: 11)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Decorative telemetry. The reactor is a fiction, but it anchors the rail's
    /// bottom edge the way the design intends.
    private var arcOutput: some View {
        VStack(alignment: .leading, spacing: 7) {
            MonoText("ARC OUTPUT", size: 9.5, tracking: 1.6)
            OutputBars()
            MonoText("3.2 GJ/s", size: 11, weight: .bold, tracking: 0,
                     color: MarkIII.goldBright)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MarkIII.color(MarkIII.gold, opacity: 0.06).clipShape(Chamfer(cut: 9)))
        .overlay(Chamfer(cut: 9)
            .strokeBorder(MarkIII.color(MarkIII.gold, opacity: 0.18), lineWidth: 1))
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneHeader
            paneBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var paneHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.title)
                    .font(MarkIII.font(22, .bold))
                    .kerning(0.5)
                    .foregroundStyle(.white)
                Text(selection.subtitle)
                    .font(MarkIII.font(13))
                    .foregroundStyle(MarkIII.color(MarkIII.dim))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                MonoText(selection.channelCode, size: 10, tracking: 1.4,
                         color: MarkIII.gold, opacity: 0.75)
                MonoText("LINK ▪ SECURE", size: 10, tracking: 1.4,
                         color: MarkIII.gold, opacity: 0.75)
            }
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MarkIII.color(MarkIII.gold, opacity: 0.18))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selection {
        case .transcription: transcriptionPane
        case .hotkey: hotkeyPane
        case .promptTemplate: templatePane
        case .general: generalPane
        case .diagnostics: diagnosticsPane
        }
    }

    // MARK: - Panes

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.providerOptions, id: \.name) { option in
                let active = option.name == store.activeProvider
                Button { store.selectProvider(option.name) } label: {
                    ChamferRow(isActive: active, isDimmed: !option.isAvailable) {
                        HStack(spacing: 12) {
                            Diamond(color: active ? MarkIII.goldBright : MarkIII.gold,
                                    filled: active, glows: active)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(MarkIII.font(15, .semibold))
                                    .foregroundStyle(.white)
                                MonoText(option.detail, size: 11, weight: .regular, tracking: 0,
                                         color: active ? MarkIII.ink : MarkIII.dim,
                                         opacity: active ? 0.78 : 1)
                            }
                            Spacer(minLength: 0)
                            if let reason = option.unavailableReason {
                                MonoText(reason, size: 10.5, tracking: 1,
                                         color: MarkIII.dim, opacity: 0.9)
                            } else if active {
                                MonoText("ONLINE", size: 10.5, weight: .bold, tracking: 1.6,
                                         color: MarkIII.onGold)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(MarkIII.goldSlab.clipShape(Chamfer(cut: 6)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!option.isAvailable)
            }

            if store.activeProviderNeedsAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    MonoText("API KEY · ENCRYPTED", size: 10, tracking: 1.8,
                             color: MarkIII.gold, opacity: 0.8)
                    ChamferRow {
                        SecureField("", text: $store.apiKey)
                            .textFieldStyle(.plain)
                            .font(MarkIII.mono(14, .medium))
                            .kerning(1.5)
                            .foregroundStyle(MarkIII.color(MarkIII.goldBright))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .onSubmit { store.saveAPIKey() }
                    }
                    Button("儲存金鑰") { store.saveAPIKey() }
                        .buttonStyle(MarkIIIButtonStyle(isPrimary: true))
                        .padding(.top, 4)
                }
                .padding(.top, 6)
            } else {
                Text("這個供應商在裝置上辨識，不需要 API Key。")
                    .font(MarkIII.font(13.5))
                    .foregroundStyle(MarkIII.color(MarkIII.dim))
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var hotkeyPane: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(HotkeyKey.allCases, id: \.self) { key in
                let active = key == store.hotkey
                Button { store.selectHotkey(key) } label: {
                    listRow(title: key.displayName,
                            meta: String(format: "0x%02X", key.keyCode),
                            active: active)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var templatePane: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(store.templateNames, id: \.self) { name in
                Button { store.selectTemplate(name) } label: {
                    listRow(title: name,
                            meta: name == store.activeTemplate ? "IN USE" : "STANDBY",
                            active: name == store.activeTemplate)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// Shared shape for the hotkey and template lists: name, mono meta line, and
    /// an ACTIVE flag on the selected row.
    private func listRow(title: String, meta: String, active: Bool) -> some View {
        ChamferRow(isActive: active) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MarkIII.font(15, .semibold))
                        .foregroundStyle(active ? Color.white : MarkIII.color(MarkIII.ink))
                    MonoText(meta, size: 11, weight: .regular, tracking: 0)
                }
                Spacer(minLength: 0)
                if active {
                    MonoText("▰ ACTIVE", size: 10.5, weight: .bold, tracking: 1.6,
                             color: MarkIII.goldBright)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 9) {
            toggleRow("登入時啟動", "SMAppService · LaunchAgent fallback",
                      isOn: Binding(get: { store.launchAtLoginEnabled },
                                    set: { _ in store.toggleLaunchAtLogin() }))
            toggleRow("啟用語音指令", "VoiceCommandProcessor",
                      isOn: Binding(get: { store.voiceCommands },
                                    set: { store.voiceCommands = $0; store.saveGeneral() }))

            ChamferRow {
                HStack(spacing: 12) {
                    Text("靜音門檻")
                        .font(MarkIII.font(15, .semibold))
                        .foregroundStyle(MarkIII.color(MarkIII.ink))
                        .frame(width: 92, alignment: .leading)
                    SkewSlider(value: $store.silenceThreshold, range: 0...0.1) {
                        store.saveGeneral()
                    }
                    MonoText(String(format: "%.3f", store.silenceThreshold),
                             size: 13, weight: .bold, tracking: 0, color: MarkIII.goldBright)
                    .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            ChamferRow {
                HStack(spacing: 12) {
                    Text("前綴詞")
                        .font(MarkIII.font(15, .semibold))
                        .foregroundStyle(MarkIII.color(MarkIII.ink))
                        .frame(width: 92, alignment: .leading)
                    TextField("— 未設定 —", text: $store.prefix)
                        .textFieldStyle(.plain)
                        .font(MarkIII.mono(13))
                        .foregroundStyle(MarkIII.color(MarkIII.ink))
                        .onSubmit { store.saveGeneral() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String,
                           isOn: Binding<Bool>) -> some View {
        ChamferRow(isActive: isOn.wrappedValue) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MarkIII.font(15, .semibold))
                        .foregroundStyle(.white)
                    MonoText(subtitle, size: 11, weight: .regular, tracking: 0)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(MarkIIIToggleStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("開啟設定檔資料夾") {
                    NSWorkspace.shared.open(URL(fileURLWithPath:
                        (Config.configPath as NSString).deletingLastPathComponent))
                }
                .buttonStyle(MarkIIIButtonStyle())
                Button("顯示錯誤記錄") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: ErrorLog.logPath)
                    ])
                }
                .buttonStyle(MarkIIIButtonStyle())
            }
            MonoText("ERROR LOG · TAIL", size: 10, tracking: 1.8,
                     color: MarkIII.gold, opacity: 0.8)
            .padding(.top, 6)
            ChamferRow {
                Text(ErrorLog.tail())
                    .font(MarkIII.mono(11.5))
                    .lineSpacing(5)
                    .foregroundStyle(MarkIII.color(MarkIII.dim))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            Spacer(minLength: 0)
        }
    }
}
