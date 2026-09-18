//
//  TreemapTests.swift
//  kivoTests
//
//  The map is only honest if a box's area really is its share of the space.
//

import Testing
import CoreGraphics
@testable import Kivo

struct TreemapTests {

    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)

    @Test("Every box gets area in proportion to its value")
    func areasAreProportional() {

        let values: [Double] = [500, 250, 125, 75, 50]
        let rects = TreemapLayout.rects(for: values, in: bounds)

        let total = values.reduce(0, +)
        let area = Double(bounds.width * bounds.height)

        for (value, rect) in zip(values, rects) {
            let expected = value / total * area
            let actual = Double(rect.width * rect.height)
            #expect(abs(actual - expected) < expected * 0.01, "area off by more than 1%")
        }
    }

    @Test("The boxes fill the space and stay inside it")
    func fillsBounds() {

        let rects = TreemapLayout.rects(for: [40, 30, 20, 6, 4], in: bounds)

        let covered = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(covered - Double(bounds.width * bounds.height)) < 1)

        for rect in rects {
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        }
    }

    @Test("No two boxes overlap")
    func noOverlap() {

        let rects = TreemapLayout.rects(for: [90, 45, 30, 22, 15, 9, 5, 3], in: bounds)

        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.width < 0.5 || overlap.height < 0.5, "boxes overlap")
            }
        }
    }

    @Test("Squarified, not sliced: boxes stay usable rather than becoming slivers")
    func staysSquarish() {

        let values = (1...30).map { Double(31 - $0) }
        let rects = TreemapLayout.rects(for: values, in: bounds)

        // A naive slice layout would put every box at full height, giving
        // the smallest a ratio in the hundreds.
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 12, "worst aspect ratio was \(worst)")
    }

    @Test("Degenerate input doesn't produce nonsense")
    func handlesEdgeCases() {

        #expect(TreemapLayout.rects(for: [], in: bounds).isEmpty)
        #expect(TreemapLayout.rects(for: [0, 0], in: bounds).allSatisfy { $0 == .zero })
        #expect(TreemapLayout.rects(for: [1, 2], in: .zero).allSatisfy { $0 == .zero })

        let single = TreemapLayout.rects(for: [1], in: bounds)
        #expect(single.count == 1)
        #expect(abs(single[0].width - bounds.width) < 0.5)
    }
}
