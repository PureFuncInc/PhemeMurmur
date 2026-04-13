import Foundation

protocol TranscriptionProvider {
    func transcribe(fileURL: URL, language: String?) async throws -> String
    func postProcess(text: String, instruction: String) async throws -> String
}
