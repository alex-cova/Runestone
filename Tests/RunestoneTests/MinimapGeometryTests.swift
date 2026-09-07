import CoreGraphics
@testable import Runestone
import XCTest

/// `MinimapGeometry` is the whole scroll transform, as a pure value type. These assert the two
/// guarantees the design rests on — the indicator never leaves the minimap's bounds, and it is
/// flush at both ends of the scroll range — plus that the click/drag inverses round-trip, across
/// short, exactly-fitting, and very large documents and under a large `textContainerInset`.
final class MinimapGeometryTests: XCTestCase {
    private let estimatedLineHeight: CGFloat = 20
    private let minimapRowHeight: CGFloat = 3
    private var scale: CGFloat { minimapRowHeight / estimatedLineHeight }

    private func geometry(
        contentOffsetY: CGFloat,
        documentHeight: CGFloat,
        boundsHeight: CGFloat = 500,
        viewportHeight: CGFloat = 500,
        insetTop: CGFloat = 0,
        minContentOffsetY: CGFloat = 0
    ) -> MinimapGeometry {
        MinimapGeometry(
            boundsHeight: boundsHeight,
            viewportHeight: viewportHeight,
            contentOffsetY: contentOffsetY,
            minimumContentOffsetY: minContentOffsetY,
            maximumContentOffsetY: max(documentHeight - viewportHeight, minContentOffsetY),
            documentHeight: documentHeight,
            textContainerInsetTop: insetTop,
            scale: scale,
            minIndicatorHeight: 6
        )
    }

    private func sweep(_ body: (CGFloat) -> Void, min: CGFloat, max: CGFloat, steps: Int = 40) {
        guard steps > 0 else { return }
        for i in 0 ... steps {
            body(min + (max - min) * CGFloat(i) / CGFloat(steps))
        }
    }

    func testIndicatorStaysInsideBoundsAcrossFullScrollRange() {
        for documentHeight: CGFloat in [120, 500, 4_000, 200_000] {
            let maxOffset = Swift.max(documentHeight - 500, 0)
            sweep({ offset in
                let g = geometry(contentOffsetY: offset, documentHeight: documentHeight)
                let rect = g.indicatorRect(width: 100)
                XCTAssertGreaterThanOrEqual(rect.minY, -0.001, "doc \(documentHeight) offset \(offset)")
                XCTAssertLessThanOrEqual(rect.maxY, 500 + 0.001, "doc \(documentHeight) offset \(offset)")
            }, min: -60, max: maxOffset + 60)
        }
    }

    func testIndicatorFlushAtBothEndsForLargeDocument() {
        let documentHeight: CGFloat = 200_000
        let maxOffset = documentHeight - 500

        let top = geometry(contentOffsetY: 0, documentHeight: documentHeight)
        XCTAssertEqual(top.indicatorRect(width: 100).minY, 0, accuracy: 0.001)

        let bottom = geometry(contentOffsetY: maxOffset, documentHeight: documentHeight)
        XCTAssertEqual(bottom.indicatorRect(width: 100).maxY, 500, accuracy: 0.001)
    }

    /// The regression the earlier row-index geometry failed: a large `textContainerInset.top`
    /// (typewriter scrolling) plus bottom overscroll must not push the indicator off either end.
    func testIndicatorFlushWithLargeTextContainerInset() {
        let lineManagerHeight: CGFloat = 200_000
        let insetTop: CGFloat = 250
        let insetBottom: CGFloat = 250
        let bottomOverscroll: CGFloat = 250
        let contentSizeHeight = lineManagerHeight + insetTop + insetBottom + bottomOverscroll
        let documentHeight = Swift.max(contentSizeHeight, insetTop + lineManagerHeight + insetBottom)
        let maxOffset = documentHeight - 500

        let top = geometry(contentOffsetY: 0, documentHeight: documentHeight, insetTop: insetTop)
        XCTAssertEqual(top.indicatorRect(width: 100).minY, 0, accuracy: 0.001)

        let bottom = geometry(contentOffsetY: maxOffset, documentHeight: documentHeight, insetTop: insetTop)
        XCTAssertEqual(bottom.indicatorRect(width: 100).maxY, 500, accuracy: 0.001)
    }

    func testClickRoundTripsToTheSameContentOffset() {
        let documentHeight: CGFloat = 60_000
        let maxOffset = documentHeight - 500
        sweep({ offset in
            let g = geometry(contentOffsetY: offset, documentHeight: documentHeight)
            let midY = g.indicatorRect(width: 100).midY
            XCTAssertEqual(g.contentOffsetY(forClickAtLocalY: midY), offset, accuracy: 0.01, "offset \(offset)")
        }, min: 0, max: maxOffset)
    }

    func testDragIsMonotonicAndFullTravelCoversEntireScrollRange() {
        let documentHeight: CGFloat = 60_000
        let maxOffset = documentHeight - 500
        let g = geometry(contentOffsetY: 0, documentHeight: documentHeight)
        let travel = 500 - g.indicatorRect(width: 100).height

        var previous = -CGFloat.greatestFiniteMagnitude
        sweep({ delta in
            let value = g.contentOffsetY(forDragDelta: delta, from: 0)
            XCTAssertGreaterThanOrEqual(value, previous - 0.001)
            previous = value
        }, min: 0, max: travel)

        XCTAssertEqual(g.contentOffsetY(forDragDelta: travel, from: 0), maxOffset, accuracy: 0.5)
        XCTAssertEqual(g.contentOffsetY(forDragDelta: 0, from: 0), 0, accuracy: 0.001)
    }

    func testShortDocumentPinsIndicatorToTopWithNoContentOffset() {
        let g = geometry(contentOffsetY: 0, documentHeight: 120)
        XCTAssertEqual(g.progress, 0)
        XCTAssertEqual(g.contentOffset, 0, accuracy: 0.001)
        XCTAssertEqual(g.indicatorRect(width: 100).minY, 0, accuracy: 0.001)
    }

    func testDegenerateInputsDoNotProduceNaNOrCrash() {
        let cases: [MinimapGeometry] = [
            MinimapGeometry(boundsHeight: 0, viewportHeight: 500, contentOffsetY: 10, minimumContentOffsetY: 0,
                            maximumContentOffsetY: 100, documentHeight: 1000, textContainerInsetTop: 0,
                            scale: scale, minIndicatorHeight: 6),
            MinimapGeometry(boundsHeight: 500, viewportHeight: 0, contentOffsetY: 10, minimumContentOffsetY: 0,
                            maximumContentOffsetY: 100, documentHeight: 1000, textContainerInsetTop: 0,
                            scale: scale, minIndicatorHeight: 6),
            MinimapGeometry(boundsHeight: 500, viewportHeight: 500, contentOffsetY: 10, minimumContentOffsetY: 0,
                            maximumContentOffsetY: 0, documentHeight: 0, textContainerInsetTop: 0,
                            scale: 0, minIndicatorHeight: 6),
        ]
        for g in cases {
            XCTAssertFalse(g.isValid)
            let rect = g.indicatorRect(width: 100)
            XCTAssertFalse(rect.minY.isNaN)
            XCTAssertFalse(rect.height.isNaN)
            XCTAssertFalse(g.contentOffset.isNaN)
            XCTAssertFalse(g.contentOffsetY(forClickAtLocalY: 42).isNaN)
            XCTAssertFalse(g.contentOffsetY(forDragDelta: 42, from: 0).isNaN)
        }
    }
}
