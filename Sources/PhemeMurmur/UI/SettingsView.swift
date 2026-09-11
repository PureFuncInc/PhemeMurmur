import AppKit
import SwiftUI

struct SettingsView: View {

    @ObservedObject var store: SettingsStore
    @State private var selection: SettingsTab = .transcription

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(DeepSpace.color(DeepSpace.starDust, opacity: 0.12))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
        }
        .frame(width: 820, height: 560)
        .background(
            RadialGradient(
                colors: [DeepSpace.color(DeepSpace.spaceVoidTop),
                         DeepSpace.color(DeepSpace.spaceVoidBottom)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 10, endRadius: 806
            )
        )
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbolName).frame(width: 19)
                        Text(tab.title)
                        Spacer()
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(selectionBackground(for: tab))
                    .foregroundStyle(selection == tab
                                     ? Color.white
                                     : DeepSpace.color(DeepSpace.starDust))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(width: 190)
        .background(DeepSpace.color(DeepSpace.spaceVoidBottom, opacity: 0.5))
    }

    @ViewBuilder
    private func selectionBackground(for tab: SettingsTab) -> some View {
        if selection == tab {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [DeepSpace.color(DeepSpace.auroraCyan, opacity: 0.16),
                             DeepSpace.color(DeepSpace.auroraViolet, opacity: 0.14)],
                    startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DeepSpace.color(DeepSpace.auroraCyan, opacity: 0.26), lineWidth: 1))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .transcription: transcriptionPane
        case .hotkey: hotkeyPane
        case .promptTemplate: templatePane
        case .general: generalPane
        case .diagnostics: diagnosticsPane
        }
    }

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle("轉錄服務", "選擇語音轉文字的供應商，並設定金鑰。")
            ForEach(store.providerOptions, id: \.name) { option in
                Button { store.selectProvider(option.name) } label: {
                    HStack {
                        Text(option.name)
                        Spacer()
                        if let reason = option.unavailableReason {
                            Text(reason)
                                .font(.system(size: 12))
                                .foregroundStyle(DeepSpace.color(DeepSpace.starDust, opacity: 0.7))
                        } else if option.name == store.activeProvider {
                            Text("使用中")
                                .font(.system(size: 11.5, weight: .bold))
                                .padding(.horizontal, 11).padding(.vertical, 4)
                                .background(Capsule().fill(LinearGradient(
                                    colors: [DeepSpace.color(DeepSpace.auroraCyan),
                                             DeepSpace.color(DeepSpace.auroraViolet)],
                                    startPoint: .leading, endPoint: .trailing)))
                                .foregroundStyle(Color.black)
                        }
                    }
                    .padding(14)
                    .background(rowBackground)
                    .opacity(option.isAvailable ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!option.isAvailable)
            }
            if store.activeProviderNeedsAPIKey {
                Text("API KEY").font(.system(size: 11.5, weight: .semibold)).kerning(1.2)
                    .foregroundStyle(DeepSpace.color(DeepSpace.starDust, opacity: 0.8))
                SecureField("", text: $store.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(rowBackground)
                    .onSubmit { store.saveAPIKey() }
                Button("儲存金鑰") { store.saveAPIKey() }
            } else {
                Text("這個供應商在裝置上辨識，不需要 API Key。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
            }
            Spacer()
        }
    }

    private var hotkeyPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneTitle("快捷鍵", "按一次開始錄音，再按一次結束；Esc 取消。")
            ForEach(HotkeyKey.allCases, id: \.self) { key in
                Button { store.selectHotkey(key) } label: {
                    HStack {
                        Text(key.displayName)
                        Spacer()
                        if key == store.hotkey {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))
                        }
                    }
                    .padding(14)
                    .background(rowBackground)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var templatePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneTitle("提示模板", "轉錄後套用的後處理指令。")
            ForEach(store.templateNames, id: \.self) { name in
                Button { store.selectTemplate(name) } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if name == store.activeTemplate {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DeepSpace.color(DeepSpace.auroraCyan))
                        }
                    }
                    .padding(14)
                    .background(rowBackground)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneTitle("一般", "這些設定會寫回 config.jsonc。")
            Toggle("登入時啟動", isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { _ in store.toggleLaunchAtLogin() }
            ))
            Toggle("啟用語音指令", isOn: $store.voiceCommands)
                .onChange(of: store.voiceCommands) { _ in store.saveGeneral() }
            HStack {
                Text("靜音門檻")
                Slider(value: $store.silenceThreshold, in: 0...0.1) { editing in
                    if !editing { store.saveGeneral() }
                }
                Text(String(format: "%.3f", store.silenceThreshold))
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack {
                Text("前綴詞")
                TextField("", text: $store.prefix)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(rowBackground)
                    .onSubmit { store.saveGeneral() }
            }
            Spacer()
        }
        .tint(DeepSpace.color(DeepSpace.auroraCyan))
    }

    private var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneTitle("診斷", "設定檔與錯誤記錄。")
            Button("開啟設定檔資料夾") {
                NSWorkspace.shared.open(URL(fileURLWithPath:
                    (Config.configPath as NSString).deletingLastPathComponent))
            }
            Button("顯示錯誤記錄") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: ErrorLog.logPath)
                ])
            }
            Spacer()
        }
    }

    private func paneTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(subtitle).font(.system(size: 13))
                .foregroundStyle(DeepSpace.color(DeepSpace.starDust))
        }
        .padding(.bottom, 4)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(DeepSpace.color(DeepSpace.starDust, opacity: 0.06))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DeepSpace.color(DeepSpace.starDust, opacity: 0.1), lineWidth: 1))
    }
}
