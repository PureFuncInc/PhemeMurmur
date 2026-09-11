import XCTest
@testable import PhemeMurmur

final class AudioLevelMeterTests: XCTestCase {

    func testReturnsRequestedSegmentCount() {
        let samples = [Float](repeating: 0.5, count: 1024)
        XCTAssertEqual(AudioLevelMeter.segmentLevels(samples, segments: 15).count, 15)
    }

    func testSilenceProducesZeros() {
        let samples = [Float](repeating: 0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertEqual(level, 0, accuracy: 0.0001)
        }
    }

    func testFullScaleProducesOne() {
        let samples = [Float](repeating: 1.0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertEqual(level, 1.0, accuracy: 0.0001)
        }
    }

    func testLevelsAreClampedToUnitRange() {
        let samples = [Float](repeating: 4.0, count: 1024)
        for level in AudioLevelMeter.segmentLevels(samples, segments: 15) {
            XCTAssertLessThanOrEqual(level, 1.0)
            XCTAssertGreaterThanOrEqual(level, 0.0)
        }
    }

    func testLoudSegmentReadsHigherThanQuietSegment() {
        var samples = [Float](repeating: 0.01, count: 1000)
        for i in 0..<100 { samples[i] = 0.9 }
        let levels = AudioLevelMeter.segmentLevels(samples, segments: 10)
        XCTAssertGreaterThan(levels[0], levels[5])
    }

    func testEmptyInputProducesZeros() {
        let levels = AudioLevelMeter.segmentLevels([], segments: 15)
        XCTAssertEqual(levels.count, 15)
        XCTAssertEqual(levels.reduce(0, +), 0, accuracy: 0.0001)
    }

    func testFewerSamplesThanSegmentsStillProducesFullArray() {
        let levels = AudioLevelMeter.segmentLevels([0.5, 0.5, 0.5], segments: 15)
        XCTAssertEqual(levels.count, 15)
    }
}
