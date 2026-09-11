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

    var symbolName: String {
        switch self {
        case .transcription: return "waveform.circle"
        case .hotkey: return "keyboard"
        case .promptTemplate: return "text.quote"
        case .general: return "gearshape"
        case .diagnostics: return "stethoscope"
        }
    }
}
