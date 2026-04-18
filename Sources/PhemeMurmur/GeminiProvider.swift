import Foundation

struct GeminiProvider: TranscriptionProvider {
    static let defaultModel = "gemini-3.1-flash-lite-preview"
    /// Placeholder written by Config.defaultConfigContent for a fresh install.
    private static let placeholderKey = "..."

    let apiKey: String
    let modelName: String

    init(apiKey: String, model: String = Self.defaultModel) {
        self.apiKey = apiKey
        self.modelName = model
    }

    var isKeyConfigured: Bool {
        !apiKey.isEmpty && apiKey != Self.placeholderKey
    }

    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)")!

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw TranscriptionError.fileReadError
        }

        let base64Audio = fileData.base64EncodedString()

        let languageLabel: String
        switch language {
            case "zh": languageLabel = "Traditional Chinese (繁體中文)"
            case let lang?: languageLabel = lang
            default: languageLabel = "Traditional Chinese (繁體中文)"
        }

        var instructions: String

        if let prompt {
            instructions = "Transcribe this audio."
            instructions += " If the audio contains no discernible speech or is silent, return exactly the string __SILENCE__ and nothing else."
            instructions += " The speaker primarily speaks \(languageLabel), with English nouns, verbs, and technical terms mixed in."
            instructions += "\n\nAfter transcribing, apply the following instruction to the transcription result and return ONLY the final result:\n\(prompt)"
        } else {
            instructions = "Transcribe this audio in \(languageLabel)."
            instructions += " If the audio contains no discernible speech or is silent, return exactly the string __SILENCE__ and nothing else."
            instructions += " The speaker primarily speaks Chinese, with English nouns, verbs, and technical terms mixed in. Preserve English words as-is without translating them into Chinese."
            instructions += " Output ONLY the exact transcription text, nothing else."
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": instructions],
                    ["inline_data": [
                        "mime_type": "audio/wav",
                        "data": base64Audio,
                    ]],
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw error
        }

        do {
            try TranscriptionService.checkHTTPResponse(response, data: data)
        } catch {
            throw error
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TranscriptionError.decodingError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
