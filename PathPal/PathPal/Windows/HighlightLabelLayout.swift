import AppKit

struct HighlightLabelRegion: Hashable {
    let windowIndex: Int
    let regionIndex: Int
    let bounds: CGRect
    let path: String

    var id: HighlightLabelRegionID {
        HighlightLabelRegionID(windowIndex: windowIndex, regionIndex: regionIndex)
    }
}

struct HighlightLabelRegionID: Hashable {
    let windowIndex: Int
    let regionIndex: Int
}

enum HighlightLabelLayout {
    private static let labelHeight: CGFloat = 26
    private static let margin: CGFloat = 10
    private static let minWidth: CGFloat = 68
    private static let maxWidth: CGFloat = 260
    private static let collisionPadding: CGFloat = 6

    private struct LabelCandidate {
        let region: HighlightLabelRegion
        let frame: CGRect
    }

    static func assignments(for regions: [HighlightLabelRegion]) -> [HighlightLabelRegionID: CGRect] {
        let groups = Dictionary(grouping: regions, by: \.windowIndex)
        let orderedWindowIndices = groups.keys.sorted { lhs, rhs in
            let lhsArea = maxArea(groups[lhs] ?? [])
            let rhsArea = maxArea(groups[rhs] ?? [])
            if lhsArea == rhsArea {
                return lhs < rhs
            }
            return lhsArea > rhsArea
        }

        var assigned: [HighlightLabelRegionID: CGRect] = [:]
        var occupied: [CGRect] = []

        for windowIndex in orderedWindowIndices {
            let group = groups[windowIndex] ?? []
            let candidates = labelCandidates(for: group)
            guard let candidate = candidates.first(where: { candidate in
                !occupied.contains { $0.intersects(candidate.frame.insetBy(dx: -collisionPadding, dy: -collisionPadding)) }
            }) else {
                continue
            }

            assigned[candidate.region.id] = candidate.frame
            occupied.append(candidate.frame)
        }

        return assigned
    }

    static func displayName(for path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        if components.count >= 3 {
            return components.suffix(2).joined(separator: "/")
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func maxArea(_ regions: [HighlightLabelRegion]) -> CGFloat {
        regions.map(area).max() ?? 0
    }

    private static func labelCandidates(for regions: [HighlightLabelRegion]) -> [LabelCandidate] {
        regions
            .sorted { lhs, rhs in
                let lhsArea = area(lhs)
                let rhsArea = area(rhs)
                if lhsArea == rhsArea {
                    return lhs.regionIndex < rhs.regionIndex
                }
                return lhsArea > rhsArea
            }
            .flatMap { region in
                frames(for: region).map { LabelCandidate(region: region, frame: $0) }
            }
    }

    private static func area(_ region: HighlightLabelRegion) -> CGFloat {
        region.bounds.width * region.bounds.height
    }

    private static func frames(for region: HighlightLabelRegion) -> [CGRect] {
        let bounds = region.bounds
        guard bounds.width >= minWidth + margin * 2,
              bounds.height >= labelHeight + margin * 2 else {
            return []
        }

        let width = labelWidth(for: displayName(for: region.path), availableWidth: bounds.width - margin * 2)
        guard width >= minWidth else { return [] }

        let left = bounds.minX + margin
        let center = bounds.midX - width / 2
        let right = bounds.maxX - margin - width
        let top = bounds.minY + margin
        let middle = bounds.midY - labelHeight / 2
        let bottom = bounds.maxY - margin - labelHeight

        let rawFrames = [
            CGRect(x: center, y: bottom, width: width, height: labelHeight),
            CGRect(x: center, y: top, width: width, height: labelHeight),
            CGRect(x: left, y: bottom, width: width, height: labelHeight),
            CGRect(x: right, y: bottom, width: width, height: labelHeight),
            CGRect(x: left, y: top, width: width, height: labelHeight),
            CGRect(x: right, y: top, width: width, height: labelHeight),
            CGRect(x: center, y: middle, width: width, height: labelHeight),
            CGRect(x: left, y: middle, width: width, height: labelHeight),
            CGRect(x: right, y: middle, width: width, height: labelHeight),
        ]

        return rawFrames.filter { bounds.contains($0) }
    }

    private static func labelWidth(for text: String, availableWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let naturalWidth = ceil(textWidth) + 43
        return min(max(naturalWidth, minWidth), min(maxWidth, availableWidth))
    }
}
