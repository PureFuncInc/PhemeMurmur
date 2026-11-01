import Foundation

public struct OpenAIProvider: TranscriptionProvider {
    public static let defaultModel = "gpt-transcribe"
    private static let postProcessModel = "gpt-5.6-luna"
    /// Reasoning effort for the post-process model. Its own default is
    /// "medium", which is slow for a one-sentence rewrite.
    private static let postProcessReasoningEffort = "low"

    public let apiKey: String
    public let modelName: String

    public init(apiKey: String, model: String = Self.defaultModel) {
        self.apiKey = apiKey
        self.modelName = model
    }

    public var requiresAPIKey: Bool { true }

    public var isKeyConfigured: Bool {
        !apiKey.isEmpty
    }

    public var supportsPrompt: Bool { true }

    func makeTranscriptionRequest(fileURL: URL, language: String?) throws -> URLRequest {
        let model = self.modelName
        let boundary = UUID().uuidString
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw TranscriptionError.fileReadError
        }

        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8("\(model)\r\n")

        if let language {
            // GPT-Transcribe replaces the singular language field with an array.
            let languageField = model == "gpt-transcribe" ? "languages[]" : "language"
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(languageField)\"\r\n\r\n")
            body.appendUTF8("\(language)\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        request.httpBody = body
        return request
    }

    public func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let request = try makeTranscriptionRequest(fileURL: fileURL, language: language)

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

        guard let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw TranscriptionError.decodingError
        }

        var text = result.text

        // OpenAI's transcription API accepts ISO-639-1 "zh" only and sometimes
        // returns Simplified Chinese characters. Force Hans→Hant via Apple's
        // ICU transform so the output matches the menu's "Traditional Chinese"
        // label. Character-level only; ambiguous mappings (干→乾/幹, 后→後/后)
        // are left as-is.
        if language == "zh", let converted = text.applyingTransform(
            StringTransform(rawValue: "Hans-Hant"),
            reverse: false
        ) {
            text = converted
        }

        if let prompt {
            text = try await postProcess(text: text, instruction: prompt)
        }

        return text
    }

    private func postProcess(text: String, instruction: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": Self.postProcessModel,
            "reasoning_effort": Self.postProcessReasoningEffort,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text],
            ],
        ]
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
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriptionError.decodingError
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
