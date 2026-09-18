import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing and van Wijk, 2000).
///
/// Areas are proportional to the values, and the algorithm keeps each
/// rectangle as close to square as it can. The naive alternative, slicing
/// the space in one direction, produces slivers a few pixels wide that
/// can't be labelled, hovered or clicked, which defeats the point of
/// drawing a map at all.
enum TreemapLayout {

    /// Rectangles in the same order as `values`, which must be sorted
    /// largest first. Values of zero or less are given an empty rectangle
    /// rather than being dropped, so indices still line up with the caller's
    /// own array.
    static func rects(for values: [Double], in bounds: CGRect) -> [CGRect] {

        guard !values.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        let usable = values.map { max($0, 0) }
        let total = usable.reduce(0, +)

        guard total > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        // Work in pixel area rather than in the original units.
        let scale = Double(bounds.width * bounds.height) / total
        let areas = usable.map { $0 * scale }

        var result: [CGRect] = []
        var rect = bounds
        var index = 0

        while index < areas.count {

            let side = Double(min(rect.width, rect.height))

            guard side > 0 else {
                result.append(contentsOf: Array(repeating: .zero, count: areas.count - index))
                break
            }

            // Grow the row while it makes the rectangles squarer, and stop
            // at the first item that would make the worst one worse.
            var row: [Double] = []
            var best = Double.infinity
            var end = index

            while end < areas.count {

                let candidate = row + [areas[end]]
                let ratio = worstRatio(candidate, side: side)

                if !row.isEmpty && ratio > best { break }

                best = ratio
                row = candidate
                end += 1
            }

            result.append(contentsOf: place(row, in: &rect))
            index = end
        }

        return result
    }

    /// The least square rectangle this row would produce. Lower is better.
    private static func worstRatio(_ areas: [Double], side: Double) -> Double {

        let sum = areas.reduce(0, +)
        guard sum > 0 else { return .infinity }

        let squared = side * side
        let sumSquared = sum * sum

        return areas.reduce(0) { worst, area in
            guard area > 0 else { return .infinity }
            return max(worst, max(squared * area / sumSquared, sumSquared / (squared * area)))
        }
    }

    /// Lays a row along the shorter side and shrinks the remaining space.
    private static func place(_ areas: [Double], in rect: inout CGRect) -> [CGRect] {

        let sum = areas.reduce(0, +)
        guard sum > 0 else { return Array(repeating: .zero, count: areas.count) }

        var rects: [CGRect] = []

        if rect.width >= rect.height {

            let thickness = CGFloat(sum / Double(rect.height))
            var y = rect.minY

            for area in areas {
                let height = CGFloat(area / Double(thickness))
                rects.append(CGRect(x: rect.minX, y: y, width: thickness, height: height))
                y += height
            }

            rect = CGRect(
                x: rect.minX + thickness,
                y: rect.minY,
                width: max(rect.width - thickness, 0),
                height: rect.height
            )

        } else {

            let thickness = CGFloat(sum / Double(rect.width))
            var x = rect.minX

            for area in areas {
                let width = CGFloat(area / Double(thickness))
                rects.append(CGRect(x: x, y: rect.minY, width: width, height: thickness))
                x += width
            }

            rect = CGRect(
                x: rect.minX,
                y: rect.minY + thickness,
                width: rect.width,
                height: max(rect.height - thickness, 0)
            )
        }

        return rects
    }
}
