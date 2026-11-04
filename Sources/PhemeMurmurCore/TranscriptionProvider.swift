import Foundation

public protocol TranscriptionProvider: Sendable {
    var modelName: String { get }
    var requiresAPIKey: Bool { get }
    var isKeyConfigured: Bool { get }
    /// Whether `postProcess` can run a prompt template's `prompt`.
    var supportsPrompt: Bool { get }
    func transcribe(fileURL: URL, language: String?) async throws -> String
    /// Rewrites a transcript as a prompt template's `prompt` instructs (translation, cleanup, etc.).
    func postProcess(text: String, prompt: String) async throws -> String
}
