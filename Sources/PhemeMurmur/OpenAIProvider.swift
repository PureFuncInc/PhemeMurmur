import Foundation

struct OpenAIProvider: TranscriptionProvider {
    static let defaultModel = "gpt-4o-mini-transcribe-2025-12-15"
    /// Placeholder written by Config.defaultConfigContent for a fresh install.
    private static let placeholderKey = "sk-proj-xxx"

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
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.appendUTF8("\(language)\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        request.httpBody = body

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
            "model": "gpt-5-nano",
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
