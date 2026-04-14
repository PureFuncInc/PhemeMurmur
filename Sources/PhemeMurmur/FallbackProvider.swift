import Foundation

/// Wraps a chain of single-model `TranscriptionProvider` instances and walks
/// the chain on HTTP 429 responses. Each model that 429s gets a 60-second
/// cooldown; requests during cooldown skip that model automatically.
final class FallbackProvider: TranscriptionProvider {
    private let chain: [String]
    private let factory: (String) -> TranscriptionProvider
    private let cooldown: TimeInterval
    private let lock = NSLock()
    private var cooledUntil: [String: Date] = [:]
    private var lastUsedModel: String?

    init(chain: [String],
         cooldown: TimeInterval = 60,
         factory: @escaping (String) -> TranscriptionProvider) {
        precondition(!chain.isEmpty, "FallbackProvider requires at least one model")
        self.chain = chain
        self.cooldown = cooldown
        self.factory = factory
    }

    var modelName: String {
        lock.lock()
        defer { lock.unlock() }
        if let last = lastUsedModel { return last }
        let now = Date()
        if let firstAvailable = chain.first(where: { (cooledUntil[$0] ?? .distantPast) <= now }) {
            return firstAvailable
        }
        return chain[0]
    }

    var isKeyConfigured: Bool {
        factory(chain[0]).isKeyConfigured
    }

    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let available = availableModels()
        if available.isEmpty {
            throw TranscriptionError.allModelsRateLimited(retryAfter: shortestRemainingCooldown())
        }

        for model in available {
            let provider = factory(model)
            do {
                print("Transcribing with model: \(model)")
                let text = try await provider.transcribe(
                    fileURL: fileURL,
                    language: language,
                    prompt: prompt
                )
                recordSuccess(model: model)
                return text
            } catch TranscriptionError.httpError(429, let message) {
                print("Model \(model) rate limited (\(message)), cooling for \(Int(cooldown))s")
                recordCooldown(model: model)
                continue
            } catch {
                throw error
            }
        }

        // Every candidate 429'd during this walk — report as a single
        // aggregated rate-limit error instead of the last raw 429 message.
        throw TranscriptionError.allModelsRateLimited(retryAfter: shortestRemainingCooldown())
    }

    // MARK: - Internal state helpers

    private func availableModels() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        return chain.filter { (cooledUntil[$0] ?? .distantPast) <= now }
    }

    private func recordSuccess(model: String) {
        lock.lock()
        defer { lock.unlock() }
        lastUsedModel = model
    }

    private func recordCooldown(model: String) {
        lock.lock()
        defer { lock.unlock() }
        cooledUntil[model] = Date().addingTimeInterval(cooldown)
    }

    private func shortestRemainingCooldown() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let remaining = chain.compactMap { model -> TimeInterval? in
            guard let until = cooledUntil[model], until > now else { return nil }
            return until.timeIntervalSince(now)
        }
        guard let min = remaining.min() else { return Int(cooldown) }
        return max(1, Int(min.rounded(.up)))
    }
}
