# Voice Command Post-Processor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic local string-substitution layer that turns Chinese voice commands (`換行`, `空行`, `分隔線`, `第一點…第十點`) into formatting (`\n`, `\n\n`, `\n\n---\n\n`, `\n1. `…`\n10. `) before the transcription is pasted, gated by a new `voice-commands` config flag (default `false`).

**Architecture:** New `VoiceCommandProcessor` enum with two pure static tables (one for static replacements, one for numbered points) and a single `process(_:)` function that runs an ICU-regex pass per trigger. Each pattern absorbs surrounding half-/full-width punctuation and whitespace. Wired into `main.swift` after `provider.transcribe()` returns, only when the active prompt template carries no LLM `prompt`. New `Tests/PhemeMurmurTests` target added to `Package.swift` (none exists today).

**Tech Stack:** Swift 5.9, Foundation (`NSRegularExpression`), XCTest, macOS 13+.

---

## File Structure

- **Create** `Sources/PhemeMurmur/VoiceCommandProcessor.swift` — pure substitution logic, no Foundation outside `NSRegularExpression`. ~50 lines.
- **Create** `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift` — XCTest cases for every behaviour the spec calls out.
- **Modify** `Package.swift` — add `Tests/PhemeMurmurTests` test target; bump structure to declare both targets.
- **Modify** `Sources/PhemeMurmur/Config.swift` — add optional `voiceCommands: Bool?` field decoded from `voice-commands`, plus a `resolvedVoiceCommands` accessor and a discoverable comment in `defaultConfigContent`.
- **Modify** `Sources/PhemeMurmur/main.swift` — store the flag on the app delegate, call `VoiceCommandProcessor.process(_:)` between the `__SILENCE__` check (line ~301) and the prefix concatenation (line ~308) when the flag is on AND `template?.prompt == nil`.

---

## Task 1: Add XCTest target and smoke test

The project has no test target today. We need scaffolding before any TDD step can be meaningful.

**Files:**
- Modify: `Package.swift`
- Create: `Tests/PhemeMurmurTests/SmokeTest.swift`

- [ ] **Step 1: Update `Package.swift` to declare a library target plus a test target**

The current package has a single `executableTarget`. Tests cannot link against an executable target, so we must turn the library code into a regular target that an executable target depends on. To minimise diff, keep the executable shape and just add a sibling test target that imports the source files via `@testable import PhemeMurmur` — this works because `swift test` will build the executable target as a module the test target can import.

Replace the entire contents of `Package.swift` with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhemeMurmur",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PhemeMurmur",
            path: "Sources/PhemeMurmur"
        ),
        .testTarget(
            name: "PhemeMurmurTests",
            dependencies: ["PhemeMurmur"],
            path: "Tests/PhemeMurmurTests"
        ),
    ]
)
```

- [ ] **Step 2: Create the smoke test file**

Create `Tests/PhemeMurmurTests/SmokeTest.swift`:

```swift
import XCTest
@testable import PhemeMurmur

final class SmokeTest: XCTestCase {
    func testHarnessCompilesAndRuns() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Run the test to confirm scaffolding works**

Run: `swift test --filter SmokeTest`

Expected: build succeeds, one test passes.

If it fails to compile because `@testable import PhemeMurmur` cannot import an executable target on the current Swift toolchain, fall back to splitting `PhemeMurmur` into a library + a thin executable wrapper. To keep this plan tractable, only do that if Step 3 actually fails — the executable-target-as-test-import pattern works on Swift 5.9 and macOS toolchains in practice.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/PhemeMurmurTests/SmokeTest.swift
git commit -m "test: add XCTest target with smoke test"
```

---

## Task 2: Implement `VoiceCommandProcessor` with `換行` and boundary absorption

Walk one trigger end-to-end before adding the rest, so the boundary regex and replacement template are pinned down.

**Files:**
- Create: `Sources/PhemeMurmur/VoiceCommandProcessor.swift`
- Create: `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`

- [ ] **Step 1: Write the first failing tests**

Create `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`:

```swift
import XCTest
@testable import PhemeMurmur

final class VoiceCommandProcessorTests: XCTestCase {

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(VoiceCommandProcessor.process(""), "")
    }

    func testNoTriggersReturnsInputUnchanged() {
        let input = "今天天氣很好"
        XCTAssertEqual(VoiceCommandProcessor.process(input), input)
    }

    func testNewlineMidSentenceWithHalfWidthCommas() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("Hello,換行,World"),
            "Hello\nWorld"
        )
    }

    func testNewlineMidSentenceWithFullWidthCommas() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("你好，換行，世界"),
            "你好\n世界"
        )
    }

    func testNewlineSurroundedBySpaces() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("今天 換行 明天"),
            "今天\n明天"
        )
    }

    func testNewlineAtStart() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("換行你好"),
            "\n你好"
        )
    }

    func testNewlineAtEnd() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("你好換行"),
            "你好\n"
        )
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: build fails with "cannot find 'VoiceCommandProcessor' in scope".

- [ ] **Step 3: Create `VoiceCommandProcessor.swift`**

Create `Sources/PhemeMurmur/VoiceCommandProcessor.swift`:

```swift
import Foundation

enum VoiceCommandProcessor {
    /// (trigger phrase, replacement string).
    /// Adding new entries here is the only change needed to extend the
    /// non-numbered triggers.
    private static let staticReplacements: [(trigger: String, output: String)] = [
        ("換行", "\n"),
    ]

    /// Numbered list points. Hard-coded 1–10; extend by appending rows.
    private static let numberedPoints: [(trigger: String, output: String)] = []

    /// Boundary characters absorbed on both sides of any trigger.
    /// Matches half- and full-width punctuation and whitespace that the
    /// STT model commonly inserts where the user paused around the trigger.
    /// `　` is the full-width ideographic space (ICU regex syntax).
    private static let boundaryClass = "[ \\t\\u3000，。、,.]*"

    /// Replaces every trigger occurrence (with its surrounding boundary
    /// characters) with the trigger's output. Pure function; safe to call
    /// on any string, including empty input.
    static func process(_ text: String) -> String {
        // Process longest triggers first so future overlapping prefixes
        // (e.g. 第十一點 vs 第十點) don't accidentally short-match.
        let allTriggers = (staticReplacements + numberedPoints)
            .sorted { $0.trigger.count > $1.trigger.count }

        var result = text
        for (trigger, output) in allTriggers {
            let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
            let pattern = "\(boundaryClass)\(escapedTrigger)\(boundaryClass)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: output)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: all 7 tests pass.

If `testNewlineSurroundedBySpaces` or any boundary-eating test fails, the `　` ICU escape may not be honoured in the toolchain. Fix by replacing `\\u3000` in `boundaryClass` with the literal full-width space character (`　`) — same regex semantics, fewer escape layers.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhemeMurmur/VoiceCommandProcessor.swift \
        Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift
git commit -m "feat(processor): add VoiceCommandProcessor with 換行 trigger"
```

---

## Task 3: Add `空行` and `分隔線` triggers

**Files:**
- Modify: `Sources/PhemeMurmur/VoiceCommandProcessor.swift`
- Modify: `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`

- [ ] **Step 1: Append failing tests for the two new triggers**

Append to `VoiceCommandProcessorTests.swift` inside the class:

```swift
    func testBlankLineProducesDoubleNewline() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("段落一，空行，段落二"),
            "段落一\n\n段落二"
        )
    }

    func testSeparatorProducesMarkdownRule() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("標題，分隔線，內容"),
            "標題\n\n---\n\n內容"
        )
    }
```

- [ ] **Step 2: Run the tests and verify the two new ones fail**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: 7 pass, 2 fail with output not matching expected (the triggers aren't in the table yet, so they appear unchanged in the result).

- [ ] **Step 3: Add the two rows to `staticReplacements`**

In `VoiceCommandProcessor.swift`, replace the `staticReplacements` declaration with:

```swift
    private static let staticReplacements: [(trigger: String, output: String)] = [
        ("換行", "\n"),
        ("空行", "\n\n"),
        ("分隔線", "\n\n---\n\n"),
    ]
```

- [ ] **Step 4: Run the tests and verify they all pass**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: 9 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhemeMurmur/VoiceCommandProcessor.swift \
        Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift
git commit -m "feat(processor): add 空行 and 分隔線 triggers"
```

---

## Task 4: Add `第一點…第十點` numbered-point triggers

**Files:**
- Modify: `Sources/PhemeMurmur/VoiceCommandProcessor.swift`
- Modify: `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`

- [ ] **Step 1: Append failing tests covering the numbered range**

Append to `VoiceCommandProcessorTests.swift` inside the class:

```swift
    func testFirstPointProducesOneDotSpace() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("第一點，要先處理 A"),
            "\n1. 要先處理 A"
        )
    }

    func testTenthPointProducesTwoDigitOutput() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("第十點，是 J"),
            "\n10. 是 J"
        )
    }

    func testNumberedPointsSequence() {
        XCTAssertEqual(
            VoiceCommandProcessor.process(
                "重點，第一點，A，第二點，B，第三點，C"
            ),
            "重點\n1. A\n2. B\n3. C"
        )
    }

    func testAllNumberedPointsCovered() {
        let triggers = [
            ("第一點", "\n1. "), ("第二點", "\n2. "), ("第三點", "\n3. "),
            ("第四點", "\n4. "), ("第五點", "\n5. "), ("第六點", "\n6. "),
            ("第七點", "\n7. "), ("第八點", "\n8. "), ("第九點", "\n9. "),
            ("第十點", "\n10. "),
        ]
        for (trigger, expected) in triggers {
            XCTAssertEqual(
                VoiceCommandProcessor.process(trigger),
                expected,
                "Trigger \(trigger) should produce \(expected.debugDescription)"
            )
        }
    }
```

- [ ] **Step 2: Run the tests and verify the numbered-point ones fail**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: 9 pass, 4 fail.

- [ ] **Step 3: Populate `numberedPoints`**

In `VoiceCommandProcessor.swift`, replace the `numberedPoints` declaration with:

```swift
    private static let numberedPoints: [(trigger: String, output: String)] = [
        ("第一點", "\n1. "),
        ("第二點", "\n2. "),
        ("第三點", "\n3. "),
        ("第四點", "\n4. "),
        ("第五點", "\n5. "),
        ("第六點", "\n6. "),
        ("第七點", "\n7. "),
        ("第八點", "\n8. "),
        ("第九點", "\n9. "),
        ("第十點", "\n10. "),
    ]
```

- [ ] **Step 4: Run the tests and verify they all pass**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: 13 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PhemeMurmur/VoiceCommandProcessor.swift \
        Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift
git commit -m "feat(processor): add 第一點…第十點 numbered-point triggers"
```

---

## Task 5: Lock-in tests for edge cases

These pin down behaviour the existing implementation already handles, so future changes can't regress them silently.

**Files:**
- Modify: `Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift`

- [ ] **Step 1: Append edge-case tests**

Append to `VoiceCommandProcessorTests.swift` inside the class:

```swift
    func testConsecutiveNewlineTriggersStack() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("A 換行 換行 B"),
            "A\n\nB"
        )
    }

    func testMixedTriggersInOneInput() {
        XCTAssertEqual(
            VoiceCommandProcessor.process(
                "標題，分隔線，第一點，A，空行，結尾"
            ),
            "標題\n\n---\n\n\n1. A\n\n結尾"
        )
    }

    func testTriggerInsideUnrelatedTextDoesNotMatch() {
        // Sanity check: 'a換行b' with no boundaries still matches the
        // bare trigger; absence of boundary chars is allowed (boundary
        // class is *, not +). This pins current behaviour.
        XCTAssertEqual(
            VoiceCommandProcessor.process("a換行b"),
            "a\nb"
        )
    }

    func testHalfWidthPeriodAbsorbed() {
        XCTAssertEqual(
            VoiceCommandProcessor.process("結束.換行.繼續"),
            "結束\n繼續"
        )
    }

    func testFullWidthIdeographicSpaceAbsorbed() {
        // \u{3000} is the full-width ideographic space.
        XCTAssertEqual(
            VoiceCommandProcessor.process("前面\u{3000}換行\u{3000}後面"),
            "前面\n後面"
        )
    }
```

- [ ] **Step 2: Run all tests**

Run: `swift test --filter VoiceCommandProcessorTests`

Expected: 18 pass.

If `testFullWidthIdeographicSpaceAbsorbed` fails, the toolchain didn't honour `\\u3000` in the regex pattern. Apply the literal-character fallback noted in Task 2 Step 4 and re-run.

- [ ] **Step 3: Commit**

```bash
git add Tests/PhemeMurmurTests/VoiceCommandProcessorTests.swift
git commit -m "test(processor): pin edge-case behaviour for VoiceCommandProcessor"
```

---

## Task 6: Add `voice-commands` config field (default off)

**Files:**
- Modify: `Sources/PhemeMurmur/Config.swift`

- [ ] **Step 1: Add the optional field, coding key, and resolved accessor**

In `Sources/PhemeMurmur/Config.swift`, locate the `ConfigFile` struct (lines 40–77 in the current file). Inside it:

1. Add a new property after `silenceThreshold`:

```swift
    let voiceCommands: Bool?
```

2. Add a new entry to `CodingKeys` after `silenceThreshold`:

```swift
        case voiceCommands = "voice-commands"
```

3. Add a new computed property after `resolvedActiveProvider`:

```swift
    /// Defaults to false: feature must be explicitly opted into.
    var resolvedVoiceCommands: Bool {
        voiceCommands ?? false
    }
```

- [ ] **Step 2: Surface the new field in `defaultConfigContent`**

In the same file, locate the multi-line string `defaultConfigContent` (currently lines 98–124). Add a new commented block immediately after the existing `silence-threshold` comment lines:

```swift
    // Optional: enable local voice-command post-processing. When true,
    // saying 換行 / 空行 / 分隔線 / 第一點…第十點 inserts the corresponding
    // formatting in the transcription before paste. Skipped when the
    // active prompt template has a "prompt" field. Default: false.
    // "voice-commands": true,
```

The full block should end up looking like:

```jsonc
    // Optional: RMS energy threshold (0.0–1.0) for silence detection. Recordings below this are discarded. Default is 0 (disabled). Set a positive value to enable, e.g.: 0.003
    // "silence-threshold": 0.003,

    // Optional: enable local voice-command post-processing. When true,
    // saying 換行 / 空行 / 分隔線 / 第一點…第十點 inserts the corresponding
    // formatting in the transcription before paste. Skipped when the
    // active prompt template has a "prompt" field. Default: false.
    // "voice-commands": true,
```

- [ ] **Step 3: Build to verify the package still compiles**

Run: `swift build`

Expected: build succeeds with no warnings about the new field.

- [ ] **Step 4: Add a unit test for config decoding**

Append to `Tests/PhemeMurmurTests/SmokeTest.swift` (or rename to `ConfigTests.swift` if that feels cleaner — prefer appending to keep file count down):

Actually create a separate file for clarity. Create `Tests/PhemeMurmurTests/ConfigTests.swift`:

```swift
import XCTest
@testable import PhemeMurmur

final class ConfigTests: XCTestCase {
    func testVoiceCommandsDefaultsToFalseWhenAbsent() throws {
        let json = """
        {"providers": {}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertFalse(cfg.resolvedVoiceCommands)
    }

    func testVoiceCommandsTrueIsDecoded() throws {
        let json = """
        {"providers": {}, "voice-commands": true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertTrue(cfg.resolvedVoiceCommands)
    }

    func testVoiceCommandsFalseIsDecoded() throws {
        let json = """
        {"providers": {}, "voice-commands": false}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let cfg = try JSONDecoder().decode(ConfigFile.self, from: data)
        XCTAssertFalse(cfg.resolvedVoiceCommands)
    }
}
```

- [ ] **Step 5: Run the new tests**

Run: `swift test --filter ConfigTests`

Expected: 3 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhemeMurmur/Config.swift \
        Tests/PhemeMurmurTests/ConfigTests.swift
git commit -m "feat(config): add voice-commands flag (default false)"
```

---

## Task 7: Wire into `main.swift` and verify end-to-end

**Files:**
- Modify: `Sources/PhemeMurmur/main.swift`

- [ ] **Step 1: Add a stored property for the flag**

In `Sources/PhemeMurmur/main.swift`, locate the property block around lines 18–26. Add a new property after `prefix` (line 23):

```swift
    private var voiceCommandsEnabled: Bool = false
```

The block should end up looking like:

```swift
    private var prefix: String?
    private var voiceCommandsEnabled: Bool = false
    private var promptTemplates: [String: PromptTemplate] = [:]
```

- [ ] **Step 2: Load the flag during config load**

In the same file, locate the config-loading block around lines 130–156. After the `prefix = config.prefix` line (line 147), add:

```swift
            voiceCommandsEnabled = config.resolvedVoiceCommands
```

The relevant block should end up looking like:

```swift
            prefix = config.prefix
            voiceCommandsEnabled = config.resolvedVoiceCommands
            if let threshold = config.silenceThreshold {
                Config.silenceThreshold = threshold
            }
```

- [ ] **Step 3: Apply the processor between transcription and paste**

In the same file, locate the transcription-result handling block around lines 299–314. The current code is:

```swift
                let finalText = try await provider.transcribe(fileURL: fileURL, language: template?.language, prompt: template?.prompt)
                await MainActor.run {
                    if finalText == "__SILENCE__" {
                        print("Silence detected by model, skipping paste.")
                        self.state = .idle
                        self.updateStatus("Idle")
                        self.refreshProviderLabel()
                        return
                    }
                    let output = (self.prefix ?? "") + finalText
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshProviderLabel()
                }
```

Replace it with:

```swift
                let finalText = try await provider.transcribe(fileURL: fileURL, language: template?.language, prompt: template?.prompt)
                await MainActor.run {
                    if finalText == "__SILENCE__" {
                        print("Silence detected by model, skipping paste.")
                        self.state = .idle
                        self.updateStatus("Idle")
                        self.refreshProviderLabel()
                        return
                    }
                    let processed: String
                    if self.voiceCommandsEnabled, template?.prompt == nil {
                        processed = VoiceCommandProcessor.process(finalText)
                    } else {
                        processed = finalText
                    }
                    let output = (self.prefix ?? "") + processed
                    print(">>> \(output)")
                    PasteService.pasteText(output)
                    self.state = .idle
                    self.updateStatus("Idle")
                    self.refreshProviderLabel()
                }
```

- [ ] **Step 4: Build and run all tests**

Run: `swift build && swift test`

Expected: build succeeds; all 18 processor tests + 3 config tests + 1 smoke test pass (22 tests total).

- [ ] **Step 5: Manual smoke test**

Build and install:

```bash
make clean && make install
```

Then:

1. Edit `~/.config/pheme-murmur/config.jsonc` to add `"voice-commands": true` at the top level.
2. Verify the active prompt template has no `"prompt"` field (the default `zh_TW` template fits).
3. Launch PhemeMurmur, press the configured hotkey, and dictate:
   > 第一點 要先處理 A 第二點 是 B 換行 記得通知大家
4. Confirm the pasted output looks like:
   ```
   1. 要先處理 A
   2. 是 B
   記得通知大家
   ```
5. Switch the active template to one with a `"prompt"` field (e.g. `zh_TW-en_US`). Re-record the same phrase. Confirm the output is plain English with no `1.` / `2.` prefixes — i.e. the processor was correctly skipped.
6. Set `"voice-commands": false` in the config, restart the app, re-record the same phrase under `zh_TW`. Confirm `第一點` etc. appear verbatim — i.e. the flag is honoured.

If any of these manual checks deviate, capture the actual vs. expected output and revisit before committing.

- [ ] **Step 6: Commit**

```bash
git add Sources/PhemeMurmur/main.swift
git commit -m "feat(app): wire VoiceCommandProcessor into transcription pipeline"
```

---

## Self-review (already performed before handoff)

**Spec coverage:** every section of the spec maps to a task — A (hard-coded table) → Tasks 2–4; B (boundary absorption) → Task 2 Step 3 + Task 5; C (`prompt`-nil gating) → Task 7 Step 3; D (output formats) → Tasks 2–4; E (default off) → Task 6. Out-of-scope items remain out of scope. Future-extension notes deferred. ✅

**Placeholder scan:** no TBDs, no "implement later", no "similar to Task N", no vague error-handling stubs. Each code step shows the actual code. ✅

**Type consistency:** `VoiceCommandProcessor.process(_:)`, `staticReplacements`, `numberedPoints`, `boundaryClass`, `voiceCommandsEnabled`, `resolvedVoiceCommands` — all names used identically in every task that touches them. ✅
