import Foundation

public protocol TranscriptionProvider: Sendable {
    var modelName: String { get }
    var requiresAPIKey: Bool { get }
    var isKeyConfigured: Bool { get }
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String
}
