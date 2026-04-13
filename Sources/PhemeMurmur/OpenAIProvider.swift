import Foundation

struct OpenAIProvider: TranscriptionProvider {
    static let defaultModel = "gpt-4o-mini-transcribe-2025-12-15"

    let apiKey: String

    func transcribe(fileURL: URL, model: String?, language: String?) async throws -> String {
        let model = model ?? Self.defaultModel
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

        let (data, response) = try await URLSession.shared.data(for: request)
        try TranscriptionService.checkHTTPResponse(response, data: data)

        guard let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw TranscriptionError.decodingError
        }

        return result.text
    }

    func postProcess(text: String, instruction: String) async throws -> String {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        try TranscriptionService.checkHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriptionError.decodingError
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
