# Model fallback on rate limit

Date: 2026-04-14
Status: Draft

## Problem

The active transcription model (currently `gemini-3.1-flash-lite-preview`) hits
Gemini free-tier rate limits quickly during normal usage. A single 429 surfaces
as `Error: API error (429): ...` in the menu and the user has to wait or
manually switch providers.

## Goal

When the active model returns HTTP 429, automatically retry the same request
against the next model in a hard-coded fallback chain (same provider), without
user interaction, and reflect the currently-used model in the menu.

Non-goals:

- Cross-provider fallback (Gemini ↔ OpenAI). Model quality, cost, and latency
  differ enough that silently swapping providers is undesirable.
- Schema changes to `config.jsonc`. The chain is hard-coded per provider type.
- Automatic retry on errors other than 429 (network failures, 5xx, decode
  errors, etc. still bubble up immediately).

## Decisions

- **Fallback scope**: model-level within the same provider.
- **Chain source**: hard-coded per `ProviderType`. No config changes, so
  existing user `config.jsonc` files stay untouched on upgrade.
- **Trigger**: only HTTP 429.
- **State strategy**: per-model cooldown. On 429, mark that model as "cooling"
  for 60 seconds; each new transcribe starts at the top of the chain, skipping
  any model still in cooldown.
- **Menu feedback**: the `Model:` row reflects whichever model actually handled
  the most recent transcribe.

### Gemini chain

```
gemini-3.1-flash-lite-preview
gemini-2.5-flash
gemini-2.0-flash-lite
```

All three are lightweight tiers; no accidental fallback to the more expensive
`pro` models.

### OpenAI chain

```
gpt-4o-mini-transcribe-2025-12-15
```

(Whatever `OpenAIProvider.defaultModel` is at implementation time.) Length-1
chain. The wrapper still wraps it for architectural uniformity, but it behaves
as a no-op fallback (never skips, never cools down meaningfully).

## Architecture

Introduce a `FallbackProvider` that conforms to `TranscriptionProvider` and
wraps the existing single-model providers (`GeminiProvider`, `OpenAIProvider`).
The rest of the app only talks to `FallbackProvider` — the existing
`providers: [String: TranscriptionProvider]` map in `AppDelegate` is unchanged
shape-wise.

```
AppDelegate.providers["Gemini"]
  = FallbackProvider(
      chain: ["gemini-3.1-flash-lite-preview",
              "gemini-2.5-flash",
              "gemini-2.0-flash-lite"],
      factory: { model in GeminiProvider(apiKey: ..., model: model) })
```

`transcribe(...)` inside the wrapper loops the chain:

1. Filter out models whose `cooledUntil[model] > now`.
2. If nothing remains, throw `TranscriptionError.allModelsRateLimited(retryAfter:)`
   with the shortest remaining cooldown as the hint.
3. For each remaining model in order, build a single-model provider via the
   factory and call its `transcribe`.
   - Success → record `lastUsedModel`, return the text.
   - `TranscriptionError.httpError(429, _)` → set `cooledUntil[model] = now + 60`,
     continue to the next model.
   - Any other error → rethrow immediately.
4. If the whole chain fails with 429, throw `allModelsRateLimited` the same way
   as step 2.

The wrapper's `modelName` getter returns, in order of preference:

1. `lastUsedModel` (what actually ran last time)
2. First non-cooling model in the chain
3. `chain.first!` as a last-resort default

This keeps the menu `Model:` row aligned with reality: right after a
successful transcribe it shows whichever model was used; before the first
request it shows the primary; during a live cooldown it shows the next one
that would be picked.

## Components & file changes

### `Sources/PhemeMurmur/GeminiProvider.swift` (modify)

- Change `modelName` from a computed wrapper around `static let defaultModel`
  to an instance property `let modelName: String`.
- Add `init(apiKey: String, model: String = Self.defaultModel)`.
- Replace the hard-coded `model = Self.defaultModel` line in `transcribe`
  with `self.modelName`.
- Keep `static let defaultModel = "gemini-3.1-flash-lite-preview"` as the
  canonical primary.

### `Sources/PhemeMurmur/OpenAIProvider.swift` (modify)

- Mirror the Gemini change: `modelName` becomes an instance property,
  `init(apiKey:, model: = defaultModel)` added.
- If Whisper's endpoint already accepts an arbitrary model string, the only
  behavioral change is that `modelName` can now be supplied externally.

### `Sources/PhemeMurmur/Config.swift` (modify)

Add a computed property on `ProviderType`:

```swift
extension ProviderType {
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

### `Sources/PhemeMurmur/TranscriptionService.swift` (modify)

Add a new case to `TranscriptionError`:

```swift
case allModelsRateLimited(retryAfter: Int)
```

with `errorDescription` like `"Rate limited, retry in 23s"`.

### `Sources/PhemeMurmur/FallbackProvider.swift` (new)

```swift
final class FallbackProvider: TranscriptionProvider {
    private let chain: [String]
    private let factory: (String) -> TranscriptionProvider
    private let cooldown: TimeInterval = 60
    private let lock = NSLock()
    private var cooledUntil: [String: Date] = [:]
    private var lastUsedModel: String?

    init(chain: [String], factory: @escaping (String) -> TranscriptionProvider)

    var modelName: String { /* see architecture section */ }
    var isKeyConfigured: Bool { factory(chain[0]).isKeyConfigured }
    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String
}
```

All reads/writes to `cooledUntil` and `lastUsedModel` are taken under `lock`.
The lock is held only around the map mutations, not around the `await` — the
HTTP call itself runs without the lock.

### `Sources/PhemeMurmur/main.swift` (modify)

- Provider construction at `setupApp` (and the config-reload path near
  `main.swift:411`) switches to building `FallbackProvider` instances:

  ```swift
  switch entry.type {
  case .openai:
      providers[name] = FallbackProvider(
          chain: entry.type.fallbackChain,
          factory: { OpenAIProvider(apiKey: entry.apiKey, model: $0) })
  case .gemini:
      providers[name] = FallbackProvider(
          chain: entry.type.fallbackChain,
          factory: { GeminiProvider(apiKey: entry.apiKey, model: $0) })
  }
  ```

- Add a private helper `refreshModelLabel()` that reads
  `activeProvider?.modelName` and writes it to `modelLabel.stringValue`. Call
  it from the `MainActor.run` block after both successful and failed transcribe
  attempts, so the menu reflects the most-recently-used model.
- Replace the existing `modelLabel?.stringValue = ...` line inside
  `rebuildProviderSubmenu()` with a call to `refreshModelLabel()` for
  consistency.

### Not changed

- `TranscriptionProvider` protocol.
- `Config.swift` JSON schema or the default config template.
- `~/.config/pheme-murmur/config.jsonc` (user file is never rewritten on
  upgrade — `createDefaultConfigIfNeeded` already guards on file existence).

## Data flow

1. User releases the hotkey → `handleRecordingStopped` → `Task { ... transcribe }`.
2. `activeProvider.transcribe(...)` is called on the `FallbackProvider`.
3. `FallbackProvider` iterates the chain (skipping cooled models), calls the
   factory to build a per-attempt single-model provider, awaits the inner
   `transcribe`.
4. On 429, marks cooldown and continues. On success, records `lastUsedModel`
   and returns.
5. Back in `main.swift`, `MainActor.run { refreshModelLabel(); paste(text) }`
   updates the menu and pastes.

## Error handling & edge cases

- **Whole chain cooling down**: throw `.allModelsRateLimited(retryAfter:)`
  where `retryAfter` is the smallest remaining cooldown. Menu shows
  `Status: Rate limited, retry in Ns`, error icon displays briefly.
- **Non-429 failure on the first attempt**: rethrown immediately, no chain
  walk. Cooldown map untouched.
- **Mid-chain non-429 failure**: rethrown immediately, earlier 429s on the
  chain are already marked cooling. Next request skips those models.
- **`Retry-After` header**: ignored for v1 (Gemini rarely sends it). Fixed 60s
  cooldown.
- **Concurrency**: transcribe is serialized by the recording flow (one hotkey
  press = one request), but the lock is present defensively to protect
  concurrent `modelName` reads from the main actor.

## Testing

The project has no existing test target in `Package.swift`, so no automated
tests are introduced as part of this change. Manual verification:

1. **Chain walk on 429**: temporarily lower `cooldown` to 5s and/or swap the
   first chain entry to a name known to 429 or 400, record a clip, and verify
   the log shows each model being tried in order and the menu `Model:` row
   updates to the successful one.
2. **Non-429 rethrow**: swap the first chain entry to a bogus model name that
   produces a 4xx other than 429 and verify the error surfaces immediately
   without walking the chain.
3. **Cooldown reset**: after a successful fallback, wait past 60s, record
   again, verify the request starts from the top of the chain and the menu
   updates back to the primary model.
4. **All-cooling error**: drop `cooldown` to something short, force every
   chain entry to 429 back-to-back, verify
   `Status: Rate limited, retry in Ns` shows up instead of a raw 429 error.

## Out of scope

- Config-driven chain overrides.
- Cross-provider fallback.
- Retry-After header parsing.
- Pro-tier Gemini models in the chain.
- Automated unit tests (no test target exists).
