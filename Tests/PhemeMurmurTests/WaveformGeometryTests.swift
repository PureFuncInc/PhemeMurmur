import XCTest
@testable import PhemeMurmur

final class WaveformGeometryTests: XCTestCase {

    func testFiveBars() {
        XCTAssertEqual(WaveformGeometry.bars(in: 1024).count, 5)
    }

    func testMiddleBarIsTallest() {
        let bars = WaveformGeometry.bars(in: 1024)
        let tallest = bars.max(by: { $0.height < $1.height })
        XCTAssertEqual(tallest, bars[2])
    }

    func testHeightsAreSymmetric() {
        let bars = WaveformGeometry.bars(in: 1024)
        XCTAssertEqual(bars[0].height, bars[4].height, accuracy: 0.01)
        XCTAssertEqual(bars[1].height, bars[3].height, accuracy: 0.01)
    }

    func testBarsAreVerticallyCentered() {
        let size: CGFloat = 1024
        for bar in WaveformGeometry.bars(in: size) {
            XCTAssertEqual(bar.midY, size / 2, accuracy: 0.01)
        }
    }

    func testBarsStayInsideCanvas() {
        let size: CGFloat = 1024
        for bar in WaveformGeometry.bars(in: size) {
            XCTAssertGreaterThanOrEqual(bar.minX, 0)
            XCTAssertGreaterThanOrEqual(bar.minY, 0)
            XCTAssertLessThanOrEqual(bar.maxX, size)
            XCTAssertLessThanOrEqual(bar.maxY, size)
        }
    }

    func testBarsScaleProportionally() {
        let small = WaveformGeometry.bars(in: 256)
        let large = WaveformGeometry.bars(in: 1024)
        XCTAssertEqual(large[2].height, small[2].height * 4, accuracy: 0.01)
    }

    func testDetailIsMinimalAtOrBelow32() {
        XCTAssertEqual(WaveformGeometry.detail(for: 16), .minimal)
        XCTAssertEqual(WaveformGeometry.detail(for: 32), .minimal)
    }

    func testDetailIsFullAbove32() {
        XCTAssertEqual(WaveformGeometry.detail(for: 64), .full)
        XCTAssertEqual(WaveformGeometry.detail(for: 1024), .full)
    }
}
