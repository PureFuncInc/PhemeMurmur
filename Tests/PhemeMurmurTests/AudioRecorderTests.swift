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
}
