import Foundation

struct TranscriptionResponse: Decodable {
    let text: String
}

struct APIErrorResponse: Decodable {
    let error: APIErrorDetail
}

struct APIErrorDetail: Decodable {
    let message: String
}

enum TranscriptionError: Error, LocalizedError {
    case fileReadError
    case httpError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .fileReadError: return "Cannot read audio file"
        case .httpError(let code, let msg): return "API error (\(code)): \(msg)"
        case .decodingError: return "Cannot parse API response"
        }
    }
}

enum TranscriptionService {
    static func transcribe(fileURL: URL, apiKey: String) async throws -> String {
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

        // model field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("gpt-4o-transcribe\r\n")

        // language field — force Traditional Chinese output
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("zh\r\n")

        // prompt field — steer toward Traditional Chinese characters
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        body.append("請使用正體中文（繁體中文）輸出。\r\n")

        // file field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.httpError(0, "Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errResp = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw TranscriptionError.httpError(httpResponse.statusCode, errResp.error.message)
            }
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw TranscriptionError.httpError(httpResponse.statusCode, body)
        }

        guard let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw TranscriptionError.decodingError
        }

        return result.text
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
