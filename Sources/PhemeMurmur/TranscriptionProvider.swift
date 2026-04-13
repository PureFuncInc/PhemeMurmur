import Foundation

protocol TranscriptionProvider {
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String
}
