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
    private static let collisionPadding: CGFloat = 6
    private static let regularMetrics = LabelMetrics(height: 26, margin: 10, minWidth: 68, maxWidth: 260, horizontalPadding: 43)
    private static let compactMetrics = LabelMetrics(height: 22, margin: 4, minWidth: 46, maxWidth: 180, horizontalPadding: 41)

    private struct LabelMetrics {
        let height: CGFloat
        let margin: CGFloat
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let horizontalPadding: CGFloat
    }

    private struct LabelCandidate {
        let region: HighlightLabelRegion
        let frame: CGRect
    }

    static func assignments(for regions: [HighlightLabelRegion]) -> [HighlightLabelRegionID: CGRect] {
        let orderedRegions = regions.sorted { lhs, rhs in
            let lhsArea = area(lhs)
            let rhsArea = area(rhs)
            if lhsArea == rhsArea {
                if lhs.windowIndex == rhs.windowIndex {
                    return lhs.regionIndex < rhs.regionIndex
                }
                return lhs.windowIndex < rhs.windowIndex
            }
            return lhsArea > rhsArea
        }

        var assigned: [HighlightLabelRegionID: CGRect] = [:]
        var occupied: [CGRect] = []

        for region in orderedRegions {
            let candidates = labelCandidates(for: region)
            guard let candidate = firstAvailableCandidate(candidates, occupied: occupied, padding: collisionPadding)
                ?? firstAvailableCandidate(candidates, occupied: occupied, padding: 0) else {
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

    private static func firstAvailableCandidate(
        _ candidates: [LabelCandidate],
        occupied: [CGRect],
        padding: CGFloat
    ) -> LabelCandidate? {
        candidates.first { candidate in
            !occupied.contains {
                $0.intersects(candidate.frame.insetBy(dx: -padding, dy: -padding))
            }
        }
    }

    private static func labelCandidates(for region: HighlightLabelRegion) -> [LabelCandidate] {
        let frames = frames(for: region, metrics: regularMetrics) + frames(for: region, metrics: compactMetrics)
        return frames.map { LabelCandidate(region: region, frame: $0) }
    }

    private static func area(_ region: HighlightLabelRegion) -> CGFloat {
        region.bounds.width * region.bounds.height
    }

    private static func frames(for region: HighlightLabelRegion, metrics: LabelMetrics) -> [CGRect] {
        let bounds = region.bounds
        guard bounds.width >= metrics.minWidth + metrics.margin * 2,
              bounds.height >= metrics.height + metrics.margin * 2 else {
            return []
        }

        let width = labelWidth(
            for: displayName(for: region.path),
            availableWidth: bounds.width - metrics.margin * 2,
            metrics: metrics
        )
        guard width >= metrics.minWidth else { return [] }

        let left = bounds.minX + metrics.margin
        let center = bounds.midX - width / 2
        let right = bounds.maxX - metrics.margin - width
        let top = bounds.minY + metrics.margin
        let middle = bounds.midY - metrics.height / 2
        let bottom = bounds.maxY - metrics.margin - metrics.height

        let rawFrames = [
            CGRect(x: center, y: bottom, width: width, height: metrics.height),
            CGRect(x: center, y: top, width: width, height: metrics.height),
            CGRect(x: left, y: bottom, width: width, height: metrics.height),
            CGRect(x: right, y: bottom, width: width, height: metrics.height),
            CGRect(x: left, y: top, width: width, height: metrics.height),
            CGRect(x: right, y: top, width: width, height: metrics.height),
            CGRect(x: center, y: middle, width: width, height: metrics.height),
            CGRect(x: left, y: middle, width: width, height: metrics.height),
            CGRect(x: right, y: middle, width: width, height: metrics.height),
        ]

        return rawFrames.filter { bounds.contains($0) }
    }

    private static func labelWidth(for text: String, availableWidth: CGFloat, metrics: LabelMetrics) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let naturalWidth = ceil(textWidth) + metrics.horizontalPadding
        return min(max(naturalWidth, metrics.minWidth), min(metrics.maxWidth, availableWidth))
    }
}
