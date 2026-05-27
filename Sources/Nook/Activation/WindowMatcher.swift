import CoreGraphics

struct AXWindowCandidate: Equatable {
    let index: Int
    let title: String
    let frame: CGRect
}

enum WindowMatcher {
    static func bestMatch(for target: WindowInfo, among candidates: [AXWindowCandidate]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if let exact = candidates.first(where: { framesEqual($0.frame, target.frame) }) {
            return exact.index
        }
        if !target.title.isEmpty,
           let byTitle = candidates.first(where: { $0.title == target.title }) {
            return byTitle.index
        }
        let nearest = candidates.min(by: {
            originDistance($0.frame, target.frame) < originDistance($1.frame, target.frame)
        })
        return nearest?.index
    }

    private static func framesEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }

    private static func originDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.origin.x - b.origin.x
        let dy = a.origin.y - b.origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
