import Foundation

protocol TranscriptionProvider {
    /// The actual model identifier this provider calls (shown in the menu for transparency).
    var modelName: String { get }
    /// False when the API key is missing or still the default placeholder from config.jsonc.
    var isKeyConfigured: Bool { get }
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String
}
