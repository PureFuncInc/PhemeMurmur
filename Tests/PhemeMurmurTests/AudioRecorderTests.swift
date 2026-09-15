import XCTest
@testable import PhemeMurmur

final class AudioRecorderTests: XCTestCase {

    func testOnLevelCanBeAssignedAndReadBack() {
        let recorder = AudioRecorder()
        var received: [Float]?
        recorder.onLevel = { levels in received = levels }
        recorder.onLevel?([0.1, 0.2])
        XCTAssertEqual(received, [0.1, 0.2])
    }

    func testOnLevelCanBeClearedWithNil() {
        let recorder = AudioRecorder()
        recorder.onLevel = { _ in XCTFail("should not be called after clearing") }
        recorder.onLevel = nil
        XCTAssertNil(recorder.onLevel)
    }

    /// Concurrently assigns/clears `onLevel` from one thread while reading it
    /// from another, simulating the audio tap thread racing the main thread's
    /// HUD wiring. Exercises the lock-guarded accessor; under TSan this would
    /// flag any unsynchronized access. Success is simply completing without
    /// crashing or hanging.
    func testConcurrentAssignmentAndReadDoesNotCrash() {
        let recorder = AudioRecorder()
        let iterations = 2000
        let writerDone = expectation(description: "writer finished")
        let readerDone = expectation(description: "reader finished")

        DispatchQueue.global().async {
            for i in 0..<iterations {
                recorder.onLevel = (i % 2 == 0) ? { _ in } : nil
            }
            writerDone.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<iterations {
                _ = recorder.onLevel
            }
            readerDone.fulfill()
        }

        wait(for: [writerDone, readerDone], timeout: 10)
    }

    // MARK: - Input format validation
    //
    // AVAudioEngine reports 0 Hz / 0 channels when the input device it is bound to
    // has gone away. Passing that to installTap raises an Objective-C exception
    // Swift cannot catch, which aborted the app. These pin the guard that turns it
    // into a thrown Swift error instead.

    func testZeroSampleRateIsNotUsable() {
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 0, channelCount: 2))
    }

    func testZeroChannelsIsNotUsable() {
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 48000, channelCount: 0))
    }

    func testTypicalHardwareFormatsAreUsable() {
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 48000, channelCount: 2))
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 44100, channelCount: 1))
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 16000, channelCount: 1))
    }

    func testNoInputDeviceErrorExplainsItselfInChinese() {
        let message = AudioRecorder.RecorderError.noInputDevice.localizedDescription
        XCTAssertEqual(message, "找不到可用的麥克風")
    }

    func testStoppingWithoutStartingReportsNoAudio() {
        let recorder = AudioRecorder()
        guard case .noAudio = recorder.stopRecording() else {
            return XCTFail("stopRecording before startRecording should report .noAudio")
        }
        XCTAssertFalse(recorder.isRecording)
    }
}
