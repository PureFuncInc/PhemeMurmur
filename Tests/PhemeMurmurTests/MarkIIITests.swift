import XCTest
import SwiftUI
@testable import PhemeMurmur

final class ChamferTests: XCTestCase {

    func testChamferCutsTopLeftAndBottomRight() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = Chamfer(cut: 10).path(in: rect).cgPath
        // SwiftUI is y-down, so the sliced corners are the ones the design cuts.
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)), "top-left must be cut away")
        XCTAssertFalse(path.contains(CGPoint(x: 98, y: 58)), "bottom-right must be cut away")
        XCTAssertTrue(path.contains(CGPoint(x: 98, y: 2)), "top-right stays square")
        XCTAssertTrue(path.contains(CGPoint(x: 2, y: 58)), "bottom-left stays square")
    }

    func testOversizedCutDoesNotFoldThePath() {
        // A cut larger than the box would otherwise produce a self-crossing
        // polygon that renders as a bow tie.
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        let path = Chamfer(cut: 500).path(in: rect).cgPath
        XCTAssertTrue(path.contains(CGPoint(x: 18, y: 2)))
        XCTAssertFalse(path.isEmpty)
    }

    func testAppKitChamferCutsTheSameVisualCorners() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = MarkIII.chamferPath(in: rect, cut: 10)
        // AppKit is y-up: visually top-left is (minX, maxY).
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 58)), "visual top-left must be cut")
        XCTAssertFalse(path.contains(CGPoint(x: 98, y: 2)), "visual bottom-right must be cut")
        XCTAssertTrue(path.contains(CGPoint(x: 98, y: 58)))
        XCTAssertTrue(path.contains(CGPoint(x: 2, y: 2)))
    }
}

final class MenuBarIconTests: XCTestCase {

    func testPulseStartsBrightAndDipsMidPeriod() {
        XCTAssertEqual(MenuBarIcon.pulsePhase(at: 0, period: 2), 1, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.pulsePhase(at: 1, period: 2), 0, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.pulsePhase(at: 2, period: 2), 1, accuracy: 0.001)
    }

    func testPulseStaysWithinUnitRange() {
        for step in 0..<200 {
            let phase = MenuBarIcon.pulsePhase(at: Double(step) * 0.037)
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThanOrEqual(phase, 1)
        }
    }

    func testSpinCompletesExactlyOneTurnPerPeriod() {
        XCTAssertEqual(MenuBarIcon.spinAngle(at: 0, period: 2), 0, accuracy: 0.001)
        XCTAssertEqual(MenuBarIcon.spinAngle(at: 1, period: 2), .pi, accuracy: 0.001)
        // A whole period wraps back to the start rather than accumulating.
        XCTAssertEqual(MenuBarIcon.spinAngle(at: 2, period: 2), 0, accuracy: 0.001)
    }

    func testAnimationCurvesSurviveAZeroPeriod() {
        // A zero period would otherwise divide by zero and produce NaN, which
        // renders as a blank status item.
        XCTAssertEqual(MenuBarIcon.pulsePhase(at: 3, period: 0), 1)
        XCTAssertEqual(MenuBarIcon.spinAngle(at: 3, period: 0), 0)
    }

    func testEveryStateGlyphIsColouredAndCorrectlySized() {
        let glyphs = [
            MenuBarIcon.recordingGlyph(pointSize: 18, phase: 0.5),
            MenuBarIcon.transcribingGlyph(pointSize: 18, angle: 1),
            MenuBarIcon.errorGlyph(pointSize: 18),
        ]
        for glyph in glyphs {
            // Template images would be recoloured to monochrome by the menu bar,
            // losing the hot/gold distinction the states rely on.
            XCTAssertFalse(glyph.isTemplate)
            XCTAssertEqual(glyph.size, NSSize(width: 18, height: 18))
        }
    }
}

final class MarkIIIFontTests: XCTestCase {

    func testBundledFacesResolveRatherThanSilentlyFallingBack() {
        MarkIII.registerFonts()
        // Font.custom falls back silently, so the NSFont lookup is the only way
        // to prove the bundled files were actually registered.
        XCTAssertNotNil(NSFont(name: "ChakraPetch-Bold", size: 12),
                        "Chakra Petch is missing from Resources/Fonts")
        XCTAssertNotNil(NSFont(name: "JetBrainsMono-Regular", size: 12),
                        "JetBrains Mono is missing from Resources/Fonts")
    }

    func testEveryWeightMapsToARealFace() {
        MarkIII.registerFonts()
        for weight in [MarkIII.Weight.regular, .medium, .semibold, .bold] {
            XCTAssertNotNil(NSFont(name: weight.displayFace, size: 12), "\(weight.displayFace)")
            XCTAssertNotNil(NSFont(name: weight.monoFace, size: 12), "\(weight.monoFace)")
        }
    }
}

final class HUDTintTests: XCTestCase {

    func testEveryPhaseHasItsOwnTint() {
        let tints = [
            HUDPhase.recording(elapsed: 1).presentation.coreTint,
            HUDPhase.transcribing(provider: "x").presentation.coreTint,
            HUDPhase.done.presentation.coreTint,
            HUDPhase.failed(message: "x").presentation.coreTint,
        ]
        // Compared as strings because tuples of Double are not Hashable.
        let keys = Set(tints.map { "\($0.r),\($0.g),\($0.b)" })
        XCTAssertEqual(keys.count, 4, "the four phases must be distinguishable by colour alone")
    }

    func testDoneWindsDownSlowerThanEveryOtherPhase() {
        // ringSpeed is seconds per revolution, so larger is slower. Done is the
        // instrument powering down and must not look busier than recording.
        let done = HUDPhase.done.presentation.ringSpeed
        XCTAssertGreaterThan(done, HUDPhase.recording(elapsed: 1).presentation.ringSpeed)
        XCTAssertGreaterThan(done, HUDPhase.transcribing(provider: "x").presentation.ringSpeed)
        XCTAssertGreaterThan(done, HUDPhase.failed(message: "x").presentation.ringSpeed)
    }

    func testTranscribingIsTheOnlyPhaseHeldOnScreen() {
        // On-device recognition returns almost instantly, so without a dwell the
        // transcribing card would flash for a few frames and read as a glitch.
        XCTAssertGreaterThan(HUDPhase.transcribing(provider: "x").presentation.minimumDwell, 0)
        XCTAssertEqual(HUDPhase.recording(elapsed: 1).presentation.minimumDwell, 0)
        XCTAssertEqual(HUDPhase.done.presentation.minimumDwell, 0)
        XCTAssertEqual(HUDPhase.failed(message: "x").presentation.minimumDwell, 0)
    }

    func testDwellIsShorterThanTheFollowingPhaseStaysUp() {
        // Otherwise the done card would be held back longer than it is shown.
        let dwell = HUDPhase.transcribing(provider: "x").presentation.minimumDwell
        XCTAssertLessThan(dwell, HUDPhase.done.presentation.autoDismissAfter ?? 0)
    }

    func testOnlyFailureFlickers() {
        XCTAssertTrue(HUDPhase.failed(message: "x").presentation.flickers)
        XCTAssertFalse(HUDPhase.recording(elapsed: 1).presentation.flickers)
        XCTAssertFalse(HUDPhase.transcribing(provider: "x").presentation.flickers)
        XCTAssertFalse(HUDPhase.done.presentation.flickers)
    }
}

final class ErrorLogTailTests: XCTestCase {

    /// `ErrorLog` writes to a fixed path derived from the config directory, so
    /// these tests drive it through the real file rather than an injected one,
    /// and restore whatever was there afterwards.
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = try? String(contentsOfFile: ErrorLog.logPath, encoding: .utf8)
    }

    override func tearDown() {
        if let saved {
            try? saved.write(toFile: ErrorLog.logPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: ErrorLog.logPath)
        }
        super.tearDown()
    }

    func testTailReportsAPlaceholderWhenThereIsNoLog() {
        try? FileManager.default.removeItem(atPath: ErrorLog.logPath)
        XCTAssertEqual(ErrorLog.tail(), "— 沒有錯誤記錄 —")
    }

    func testTailShowsContextAndMessageOfTheMostRecentEntries() {
        try? FileManager.default.removeItem(atPath: ErrorLog.logPath)
        ErrorLog.append(context: "transcribe", message: "boom")

        let tail = ErrorLog.tail()
        XCTAssertTrue(tail.contains("transcribe"), tail)
        XCTAssertTrue(tail.contains("boom"), tail)
        // The raw key=value encoding is for machines, not the console panel.
        XCTAssertFalse(tail.contains("context="), tail)
        XCTAssertFalse(tail.contains("ts="), tail)
    }

    func testTailKeepsOnlyTheRequestedNumberOfLines() {
        try? FileManager.default.removeItem(atPath: ErrorLog.logPath)
        for i in 0..<6 { ErrorLog.append(context: "c\(i)", message: "m\(i)") }

        let tail = ErrorLog.tail(lines: 2)
        XCTAssertEqual(tail.split(separator: "\n").count, 2)
        // The newest entries are the ones worth showing.
        XCTAssertTrue(tail.contains("m5"), tail)
        XCTAssertFalse(tail.contains("m0"), tail)
    }

    func testTailKeepsQuotedMessagesIntact() {
        try? FileManager.default.removeItem(atPath: ErrorLog.logPath)
        ErrorLog.append(context: "config-parse", message: "unexpected token at line 4")

        XCTAssertTrue(ErrorLog.tail().contains("unexpected token at line 4"), ErrorLog.tail())
    }
}

final class VoiceHUDLayoutTests: XCTestCase {

    @MainActor
    private func fittingSize(_ view: VoiceHUDView) -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    private var quietLevels: [Float] { Array(repeating: 0.1, count: 15) }

    @MainActor
    func testEveryPhaseMeasuresTheSameForABatchProvider() {
        MarkIII.registerFonts()
        let phases: [HUDPhase] = [
            .recording(elapsed: 7),
            .transcribing(provider: "OpenAI"),
            .done,
            .failed(message: "尚未設定轉錄服務"),
        ]
        let sizes = phases.map { fittingSize(VoiceHUDView(phase: $0, levels: quietLevels)) }
        for size in sizes.dropFirst() {
            // A size change here would make the panel resize and re-centre as
            // the state advances, which is exactly what the HUD must not do.
            XCTAssertEqual(size.width, sizes[0].width, accuracy: 0.5)
            XCTAssertEqual(size.height, sizes[0].height, accuracy: 0.5)
        }
    }

    @MainActor
    func testEveryPhaseMeasuresTheSameWithTheTranscriptAreaReserved() {
        MarkIII.registerFonts()
        let sizes = [
            VoiceHUDView(phase: .recording(elapsed: 3), levels: quietLevels,
                         transcript: "", reservesTranscript: true),
            VoiceHUDView(phase: .recording(elapsed: 3), levels: quietLevels,
                         transcript: "ㄗㄨㄥˋ", reservesTranscript: true),
            VoiceHUDView(phase: .recording(elapsed: 3), levels: quietLevels,
                         transcript: String(repeating: "很長的一段話", count: 12),
                         reservesTranscript: true),
            VoiceHUDView(phase: .transcribing(provider: "Apple"), levels: quietLevels,
                         transcript: "短", reservesTranscript: true),
            // The done card swaps the live preview for the pasted text; that
            // must not change the card's size either.
            VoiceHUDView(phase: .done, levels: quietLevels,
                         transcript: String(repeating: "貼上的文字", count: 20),
                         transcriptIsLive: false, reservesTranscript: true),
        ].map(fittingSize)

        for size in sizes.dropFirst() {
            XCTAssertEqual(size.width, sizes[0].width, accuracy: 0.5)
            XCTAssertEqual(size.height, sizes[0].height, accuracy: 0.5)
        }
    }

    @MainActor
    func testALongErrorMessageDoesNotWidenTheCard() {
        MarkIII.registerFonts()
        let short = fittingSize(VoiceHUDView(phase: .done, levels: quietLevels))
        let long = fittingSize(VoiceHUDView(
            phase: .failed(message: "網路錯誤 (HTTP 500)，請稍後再試一次，或改用其他轉錄服務"),
            levels: quietLevels))
        XCTAssertEqual(long.width, short.width, accuracy: 0.5)
    }
}
