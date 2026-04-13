import Foundation

struct GeminiProvider: TranscriptionProvider {
    static let defaultModel = "gemini-3.1-flash-lite-preview"

    let apiKey: String

    func transcribe(fileURL: URL, language: String?) async throws -> String {
        let model = Self.defaultModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

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

        let prompt = "Transcribe this audio in \(languageLabel). The speaker primarily speaks Chinese, with English nouns, verbs, and technical terms mixed in. Preserve English words as-is without translating them into Chinese. Output ONLY the exact transcription text, nothing else."

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
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

        let (data, response) = try await URLSession.shared.data(for: request)
        try TranscriptionService.checkHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TranscriptionError.decodingError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func postProcess(text: String, instruction: String) async throws -> String {
        let model = Self.defaultModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": "\(instruction)\n\n\(text)"]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try TranscriptionService.checkHTTPResponse(response, data: data)

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
