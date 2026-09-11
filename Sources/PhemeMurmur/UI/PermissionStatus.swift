import AppKit
import AVFoundation

enum PermissionKind {
    case accessibility
    case microphone

    var title: String {
        switch self {
        case .accessibility: return "輔助使用"
        case .microphone: return "麥克風"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: return "監聽快捷鍵並把文字貼進其他 app"
        case .microphone: return "錄下你的聲音以進行轉錄"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        }
    }
}

struct PermissionItem {
    let kind: PermissionKind
    let granted: Bool
}

enum PermissionStatus {

    static func items(accessibility: Bool, microphone: AVAuthorizationStatus) -> [PermissionItem] {
        [
            PermissionItem(kind: .accessibility, granted: accessibility),
            PermissionItem(kind: .microphone, granted: microphone == .authorized),
        ]
    }

    static func current() -> [PermissionItem] {
        items(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    static func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
