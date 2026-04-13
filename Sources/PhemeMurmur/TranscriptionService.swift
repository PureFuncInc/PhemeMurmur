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
    static func checkHTTPResponse(_ response: URLResponse, data: Data) throws {
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
    }
}

extension Data {
    mutating func appendUTF8(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
