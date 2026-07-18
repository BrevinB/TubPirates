import SwiftUI

/// Ambient soap bubbles drifting up the menu screen. Pure decoration:
/// deterministic per-bubble parameters, one Canvas, no state churn.
struct RisingBubblesView: View {
    private struct Bubble {
        let baseX: Double        // 0...1 across the width
        let radius: Double
        let riseDuration: Double // seconds for one bottom-to-top trip
        let phase: Double        // 0...1 loop offset
        let sway: Double         // horizontal drift amplitude (pt)
        let swaySpeed: Double
        let opacity: Double
    }

    private static let bubbles: [Bubble] = {
        // Fixed seed → identical, stable layout every launch.
        var rng = SplitMix(seed: 0xB0BB1E5)
        return (0..<14).map { _ in
            Bubble(
                baseX: rng.next(in: 0.03...0.97),
                radius: rng.next(in: 4...13),
                riseDuration: rng.next(in: 14...26),
                phase: rng.next(in: 0...1),
                sway: rng.next(in: 6...18),
                swaySpeed: rng.next(in: 0.3...0.7),
                opacity: rng.next(in: 0.25...0.55)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for bubble in Self.bubbles {
                    let progress = ((t / bubble.riseDuration) + bubble.phase)
                        .truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.08 - 1.16 * progress)
                    let x = bubble.baseX * size.width
                        + sin(t * bubble.swaySpeed + bubble.phase * .pi * 2) * bubble.sway
                    let rect = CGRect(
                        x: x - bubble.radius, y: y - bubble.radius,
                        width: bubble.radius * 2, height: bubble.radius * 2
                    )
                    // Soap-bubble look: translucent white fill + brighter rim + highlight dot.
                    context.opacity = bubble.opacity
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: 1.2)
                    let highlight = CGRect(
                        x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.18,
                        width: rect.width * 0.24, height: rect.height * 0.24
                    )
                    context.fill(Path(ellipseIn: highlight), with: .color(.white))
                }
            }
        }
    }

    /// Tiny deterministic RNG so bubble layout never shifts between launches.
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(in range: ClosedRange<Double>) -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            let unit = Double(z ^ (z >> 31)) / Double(UInt64.max)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        RisingBubblesView()
    }
    .ignoresSafeArea()
}
