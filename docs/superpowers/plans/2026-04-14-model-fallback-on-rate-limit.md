# Model Fallback on Rate Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On HTTP 429 from a transcription provider, automatically retry the request against the next model in a hard-coded per-provider fallback chain, using a 60s per-model cooldown, and reflect the model that actually handled the request in the menu bar.

**Architecture:** Introduce a `FallbackProvider` wrapper that conforms to the existing `TranscriptionProvider` protocol. It owns a chain of model names plus a factory closure that builds a single-model provider per attempt. `GeminiProvider` and `OpenAIProvider` are refactored to accept a `model` parameter on init. Each `ProviderType` exposes a hard-coded `fallbackChain`. `AppDelegate` wraps every configured provider in a `FallbackProvider` at construction time. After every transcribe attempt the menu's `Model:` row is refreshed from the wrapper's `modelName` getter.

**Tech Stack:** Swift, AppKit, URLSession, NSLock.

**Spec:** `docs/superpowers/specs/2026-04-14-model-fallback-on-rate-limit-design.md`

---

## File Structure

| File | Role | Action |
|------|------|--------|
| `Sources/PhemeMurmur/GeminiProvider.swift` | Single-model Gemini transcription call | Modify: `modelName` becomes instance-stored, new `init(apiKey:model:)` |
| `Sources/PhemeMurmur/OpenAIProvider.swift` | Single-model OpenAI transcription call | Modify: same pattern as Gemini |
| `Sources/PhemeMurmur/Config.swift` | Provider type enum | Modify: add `fallbackChain` computed property on `ProviderType` |
| `Sources/PhemeMurmur/TranscriptionService.swift` | Shared error types | Modify: add `allModelsRateLimited(retryAfter:)` case |
| `Sources/PhemeMurmur/FallbackProvider.swift` | Chain-walking wrapper | Create |
| `Sources/PhemeMurmur/main.swift` | AppDelegate provider wiring | Modify: construct `FallbackProvider` wrappers, add `refreshModelLabel()` helper |

Each provider file keeps its single responsibility (one model = one HTTP call). The chain logic lives in its own file so unit-testing later is straightforward. No file grows disproportionately.

---

## Task 1: Parameterize `GeminiProvider` by model name

**Files:**
- Modify: `Sources/PhemeMurmur/GeminiProvider.swift`

- [ ] **Step 1: Change `modelName` to an instance property and add init**

Replace the top of the struct (`Sources/PhemeMurmur/GeminiProvider.swift:1-15`) with:

```swift
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
```

- [ ] **Step 2: Use `self.modelName` inside `transcribe`**

In `Sources/PhemeMurmur/GeminiProvider.swift` find `func transcribe(fileURL:...)` and replace its first two lines:

```swift
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let model = Self.defaultModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
```

with:

```swift
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)")!
```

- [ ] **Step 3: Build and confirm no compile errors**

Run: `swift build -c release 2>&1 | tail -20`
Expected: `Build complete!`. There will be a failure in `main.swift` only if you accidentally introduced a label typo — the old call site `GeminiProvider(apiKey: entry.apiKey)` still compiles because `model` has a default value.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhemeMurmur/GeminiProvider.swift
git commit -m "$(cat <<'EOF'
refactor(gemini): accept model name via init so the caller can pick a variant

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Parameterize `OpenAIProvider` by model name

**Files:**
- Modify: `Sources/PhemeMurmur/OpenAIProvider.swift`

- [ ] **Step 1: Change `modelName` to an instance property and add init**

Replace the top of the struct (`Sources/PhemeMurmur/OpenAIProvider.swift:1-15`) with:

```swift
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
```

- [ ] **Step 2: Use `self.modelName` inside `transcribe`**

In `Sources/PhemeMurmur/OpenAIProvider.swift` find the `transcribe` function and replace:

```swift
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let model = Self.defaultModel
```

with:

```swift
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        let model = self.modelName
```

(Keeping the local `model` binding means the rest of the function — which uses `"\(model)\r\n"` in the multipart body — needs no further changes.)

- [ ] **Step 3: Build and confirm**

Run: `swift build -c release 2>&1 | tail -20`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhemeMurmur/OpenAIProvider.swift
git commit -m "$(cat <<'EOF'
refactor(openai): accept model name via init to match gemini provider

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add fallback chain to `ProviderType` and new error case

**Files:**
- Modify: `Sources/PhemeMurmur/Config.swift`
- Modify: `Sources/PhemeMurmur/TranscriptionService.swift`

- [ ] **Step 1: Add `fallbackChain` computed property on `ProviderType`**

In `Sources/PhemeMurmur/Config.swift`, after the existing `enum ProviderType` (around line 11), add this extension right after the enum's closing brace:

```swift
extension ProviderType {
    /// Hard-coded ordered list of model names to try for this provider.
    /// Intended for automatic fallback when the primary model returns HTTP 429.
    var fallbackChain: [String] {
        switch self {
        case .gemini:
            return [
                "gemini-3.1-flash-lite-preview",
                "gemini-2.5-flash",
                "gemini-2.0-flash-lite",
            ]
        case .openai:
            return [OpenAIProvider.defaultModel]
        }
    }
}
```

- [ ] **Step 2: Add `allModelsRateLimited` error case**

In `Sources/PhemeMurmur/TranscriptionService.swift`, replace the `TranscriptionError` enum (lines 15-27) with:

```swift
enum TranscriptionError: Error, LocalizedError {
    case fileReadError
    case httpError(Int, String)
    case decodingError
    case allModelsRateLimited(retryAfter: Int)

    var errorDescription: String? {
        switch self {
        case .fileReadError: return "Cannot read audio file"
        case .httpError(let code, let msg): return "API error (\(code)): \(msg)"
        case .decodingError: return "Cannot parse API response"
        case .allModelsRateLimited(let retryAfter):
            return "Rate limited, retry in \(retryAfter)s"
        }
    }
}
```

- [ ] **Step 3: Build and confirm**

Run: `swift build -c release 2>&1 | tail -20`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhemeMurmur/Config.swift Sources/PhemeMurmur/TranscriptionService.swift
git commit -m "$(cat <<'EOF'
feat(provider): add per-type fallback chain and rate-limited error case

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Implement `FallbackProvider`

**Files:**
- Create: `Sources/PhemeMurmur/FallbackProvider.swift`

- [ ] **Step 1: Add the new file to the Swift package sources**

Swift Package Manager auto-discovers files under `Sources/PhemeMurmur/`, so no `Package.swift` edit is needed. Confirm by inspecting:

Run: `head -20 Package.swift`
Expected: A target pointing at `Sources/PhemeMurmur` without an explicit `sources:` list.

- [ ] **Step 2: Write `FallbackProvider.swift`**

Create `Sources/PhemeMurmur/FallbackProvider.swift` with the following content:

```swift
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
```


- [ ] **Step 3: Build and confirm**

Run: `swift build -c release 2>&1 | tail -30`
Expected: `Build complete!` with no errors. Warnings about the trailing
statements after `throw` are acceptable if any appear — if Swift complains
about an actual error, revisit the function body.

- [ ] **Step 4: Commit**

```bash
git add Sources/PhemeMurmur/FallbackProvider.swift
git commit -m "$(cat <<'EOF'
feat(provider): add FallbackProvider that walks a chain on 429 with cooldown

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire `FallbackProvider` into `AppDelegate` and refresh the menu label

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift`

- [ ] **Step 1: Replace provider construction in `setupApp`**

In `Sources/PhemeMurmur/main.swift` around lines 109-116, replace:

```swift
            for (name, entry) in entries {
                switch entry.type {
                case .openai:
                    providers[name] = OpenAIProvider(apiKey: entry.apiKey)
                case .gemini:
                    providers[name] = GeminiProvider(apiKey: entry.apiKey)
                }
            }
```

with:

```swift
            for (name, entry) in entries {
                providers[name] = Self.makeProvider(for: entry)
            }
```

- [ ] **Step 2: Replace provider construction in `reloadProvidersFromConfig`**

In `Sources/PhemeMurmur/main.swift` around lines 408-414, replace:

```swift
        for (n, entry) in config.resolvedProviders {
            switch entry.type {
            case .openai:
                providers[n] = OpenAIProvider(apiKey: entry.apiKey)
            case .gemini:
                providers[n] = GeminiProvider(apiKey: entry.apiKey)
            }
        }
```

with:

```swift
        for (n, entry) in config.resolvedProviders {
            providers[n] = Self.makeProvider(for: entry)
        }
```

- [ ] **Step 3: Add the shared `makeProvider` factory**

Still in `Sources/PhemeMurmur/main.swift`, add this static helper next to
`makeLabelMenuItem` (search for `private static func makeLabelMenuItem`):

```swift
    private static func makeProvider(for entry: ProviderEntry) -> TranscriptionProvider {
        let chain = entry.type.fallbackChain
        switch entry.type {
        case .openai:
            return FallbackProvider(chain: chain) { model in
                OpenAIProvider(apiKey: entry.apiKey, model: model)
            }
        case .gemini:
            return FallbackProvider(chain: chain) { model in
                GeminiProvider(apiKey: entry.apiKey, model: model)
            }
        }
    }
```

- [ ] **Step 4: Add `refreshModelLabel` helper and call it from the transcribe task**

Still in `Sources/PhemeMurmur/main.swift`, find the `rebuildProviderSubmenu` function (search for `modelLabel?.stringValue = activeProvider.map`). Replace:

```swift
        providerMenuItem?.title = "Provider: \(activeProviderName)"
        modelLabel?.stringValue = activeProvider.map { "Model: \($0.modelName)" } ?? "Model: —"
    }
```

with:

```swift
        providerMenuItem?.title = "Provider: \(activeProviderName)"
        refreshModelLabel()
    }

    private func refreshModelLabel() {
        modelLabel?.stringValue = activeProvider.map { "Model: \($0.modelName)" } ?? "Model: —"
    }
```

- [ ] **Step 5: Call `refreshModelLabel` from the transcribe completion handlers**

In the transcribe `Task { ... }` block (around `main.swift:275-294`), update both the success and error `MainActor.run` closures:

Replace the success block:

```swift
                await MainActor.run {
                    let output = (self.prefix ?? "") + finalText
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                }
```

with:

```swift
                await MainActor.run {
                    let output = (self.prefix ?? "") + finalText
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshModelLabel()
                }
```

And replace the error block:

```swift
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)")
                    self.showErrorIcon()
                }
            }
```

with:

```swift
            } catch {
                await MainActor.run {
                    print("Transcription failed: \(error)")
                    self.state = .idle
                    self.updateStatus("Error: \(error.localizedDescription)")
                    self.showErrorIcon()
                    self.refreshModelLabel()
                }
            }
```

- [ ] **Step 6: Build and confirm**

Run: `swift build -c release 2>&1 | tail -30`
Expected: `Build complete!`.

- [ ] **Step 7: Rebuild the app bundle**

Run: `make app 2>&1 | tail -10`
Expected: Output ends with `Injected GitCommitHash=...` and a successful codesign line; no compiler errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "$(cat <<'EOF'
feat(menu): wrap providers in FallbackProvider and refresh Model row per transcribe

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Manual verification

**Files:** none (runtime testing only)

The project has no automated tests, so this task walks through the spec's
manual verification scenarios against the real running app. Each scenario
gets its own checkbox so the agent can report which pass/fail.

- [ ] **Step 1: Happy path — primary model works**

Run: `make install`
Expected: Menu bar app restarts, opening the menu shows
`Model: gemini-3.1-flash-lite-preview` (or whatever the first chain entry
is for the currently active provider).

Record a short clip with the hotkey. Check the console log
(`log stream --process PhemeMurmur --predicate 'eventMessage CONTAINS "Transcribing with model"' --style compact`
or just read the app's stdout if you launched it from a terminal with
`open PhemeMurmur.app/Contents/MacOS/PhemeMurmur`) and confirm it printed
`Transcribing with model: gemini-3.1-flash-lite-preview` and then
`>>> <your transcription>`. Menu `Model:` row remains unchanged.

- [ ] **Step 2: Non-429 failure is rethrown immediately**

Temporarily edit `Sources/PhemeMurmur/Config.swift` and change the first
entry of the Gemini chain to a bogus name:

```swift
case .gemini:
    return [
        "gemini-DOES-NOT-EXIST",
        "gemini-2.5-flash",
        "gemini-2.0-flash-lite",
    ]
```

Run: `make install`

Record a clip. Expected: Gemini returns 4xx (usually 400 or 404, not 429);
the menu immediately shows
`Status: Error: API error (400): ...` without walking the chain. The log
prints only one `Transcribing with model: gemini-DOES-NOT-EXIST` line.

Revert the chain change:

```bash
git checkout Sources/PhemeMurmur/Config.swift
```

- [ ] **Step 3: 429 walk and menu update**

Temporarily lower the cooldown and set the first chain entry to a very
small quota model that you know will 429 on your account. If you don't
have one handy, modify `FallbackProvider.init` to treat any `httpError`
as 429 for test purposes — but remember to revert.

A less invasive approach: in `FallbackProvider.swift`, inside the
`catch TranscriptionError.httpError(429, let message)` branch, temporarily
also match 400:

```swift
            } catch TranscriptionError.httpError(let code, let message)
                    where code == 429 || code == 400 {
```

and set the first chain entry to the bogus name from Step 2 so it returns
400.

Run: `make install`, record a clip.

Expected log:

```
Transcribing with model: gemini-DOES-NOT-EXIST
Model gemini-DOES-NOT-EXIST rate limited (...), cooling for 60s
Transcribing with model: gemini-2.5-flash
>>> <your transcription>
```

Menu `Model:` row now shows `Model: gemini-2.5-flash`.

Revert the temporary changes:

```bash
git checkout Sources/PhemeMurmur/Config.swift Sources/PhemeMurmur/FallbackProvider.swift
make install
```

- [ ] **Step 4: Cooldown expiry resets to the top of the chain**

With the temporary 400-as-429 hack from Step 3 still in place, lower the
cooldown constant to 5 seconds in `FallbackProvider`:

```swift
init(chain: [String],
     cooldown: TimeInterval = 5,
     factory: @escaping (String) -> TranscriptionProvider) {
```

Run: `make install`, record a clip (fallback happens), wait 6 seconds,
record a second clip.

Expected: the second recording's log starts again with
`Transcribing with model: gemini-DOES-NOT-EXIST`, meaning the cooldown
expired and the chain restarted at the top.

Revert all test changes:

```bash
git checkout Sources/PhemeMurmur/Config.swift Sources/PhemeMurmur/FallbackProvider.swift
make install
```

- [ ] **Step 5: All-cooling → `allModelsRateLimited`**

Set cooldown back to a small value (e.g. `30`) and force every model in
the Gemini chain to the bogus name, with the 400-as-429 match still in
place:

```swift
case .gemini:
    return [
        "gemini-DOES-NOT-EXIST-1",
        "gemini-DOES-NOT-EXIST-2",
        "gemini-DOES-NOT-EXIST-3",
    ]
```

Run: `make install`, record a clip. Expected: the three chain entries are
each tried once (three `Transcribing with model: ...` log lines, three
`cooling for ...` lines), and then the status row shows
`Status: Error: Rate limited, retry in Ns` instead of a raw 429 / 400
message.

Revert all test changes one last time:

```bash
git checkout Sources/PhemeMurmur/Config.swift Sources/PhemeMurmur/FallbackProvider.swift
make install
```

- [ ] **Step 6: Confirm tree is clean and the app runs with production chain**

Run: `git status`
Expected: Only the committed plan tasks remain, no uncommitted edits to
`Config.swift` / `FallbackProvider.swift`.

Run: `make install`
Expected: App launches; open menu; confirm `Model: gemini-3.1-flash-lite-preview`
is shown.

No commit for this task — it is pure verification.
