import Foundation

enum SettingsTab: CaseIterable, Hashable {
    case transcription
    case hotkey
    case promptTemplate
    case general
    case diagnostics

    var title: String {
        switch self {
        case .transcription: return "轉錄服務"
        case .hotkey: return "快捷鍵"
        case .promptTemplate: return "提示模板"
        case .general: return "一般"
        case .diagnostics: return "診斷"
        }
    }

    /// Rail glyph. The Mark III console uses typographic marks rather than SF
    /// Symbols so the rail keeps the same drawn-instrument feel as the rest of
    /// the armour.
    var glyph: String {
        switch self {
        case .transcription: return "◈"
        case .hotkey: return "⌁"
        case .promptTemplate: return "❝"
        case .general: return "⚙"
        case .diagnostics: return "✚"
        }
    }

    /// Channel code printed at the top right of the detail pane.
    var channelCode: String {
        switch self {
        case .transcription: return "CH-01 / TRANSCRIBE"
        case .hotkey: return "CH-02 / TRIGGER"
        case .promptTemplate: return "CH-03 / PROTOCOL"
        case .general: return "CH-04 / SYSTEM"
        case .diagnostics: return "CH-05 / DIAGNOSTIC"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "選擇語音轉文字的供應商，並設定金鑰。"
        case .hotkey: return "按一次開始錄音，再按一次結束；Esc 取消。"
        case .promptTemplate: return "轉錄後套用的後處理指令。"
        case .general: return "這些設定會寫回 config.jsonc。"
        case .diagnostics: return "設定檔與錯誤記錄。"
        }
    }
}
