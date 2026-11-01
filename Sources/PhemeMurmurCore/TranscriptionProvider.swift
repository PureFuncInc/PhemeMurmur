import Foundation

public protocol TranscriptionProvider: Sendable {
    var modelName: String { get }
    var requiresAPIKey: Bool { get }
    var isKeyConfigured: Bool { get }
    /// Whether `transcribe` accepts a post-processing `prompt`.
    var supportsPrompt: Bool { get }
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String
}
