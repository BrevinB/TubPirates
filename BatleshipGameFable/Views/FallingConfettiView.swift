import SwiftUI

/// Celebration confetti drifting down the victory screen — the festive twin
/// of RisingBubblesView: deterministic pieces, one Canvas, no state churn.
struct FallingConfettiView: View {
    private struct Piece {
        let baseX: Double        // 0...1 across the width
        let width: Double
        let height: Double
        let fallDuration: Double
        let phase: Double
        let sway: Double
        let swaySpeed: Double
        let spinSpeed: Double
        let colorIndex: Int
    }

    private static let palette: [Color] = [
        Color(red: 1, green: 0.75, blue: 0.2),   // gold
        Color(red: 0.95, green: 0.4, blue: 0.45), // coral
        Color(red: 0.35, green: 0.75, blue: 0.95), // sky
        Color(red: 0.5, green: 0.85, blue: 0.5),  // mint
        Color(red: 0.75, green: 0.55, blue: 0.95), // lilac
    ]

    private static let pieces: [Piece] = {
        var rng = SplitMix(seed: 0xC0FFE771)
        return (0..<22).map { index in
            Piece(
                baseX: rng.next(in: 0.02...0.98),
                width: rng.next(in: 7...13),
                height: rng.next(in: 4...7),
                fallDuration: rng.next(in: 5...11),
                phase: rng.next(in: 0...1),
                sway: rng.next(in: 10...30),
                swaySpeed: rng.next(in: 0.6...1.4),
                spinSpeed: rng.next(in: 1.5...4.0),
                colorIndex: index % palette.count
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for piece in Self.pieces {
                    let progress = ((t / piece.fallDuration) + piece.phase)
                        .truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1.12 * progress - 0.06)
                    let x = piece.baseX * size.width
                        + sin(t * piece.swaySpeed + piece.phase * .pi * 2) * piece.sway
                    let spin = Angle(radians: t * piece.spinSpeed + piece.phase * .pi * 2)

                    var pieceContext = context
                    pieceContext.translateBy(x: x, y: y)
                    pieceContext.rotate(by: spin)
                    // Cosine wobble fakes the 3D tumble of a paper strip.
                    let squash = 0.35 + 0.65 * abs(cos(t * piece.spinSpeed * 0.7 + piece.phase))
                    let rect = CGRect(
                        x: -piece.width / 2, y: -piece.height * squash / 2,
                        width: piece.width, height: piece.height * squash
                    )
                    pieceContext.opacity = 0.9
                    pieceContext.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(Self.palette[piece.colorIndex])
                    )
                }
            }
        }
    }

    /// Tiny deterministic RNG so confetti layout never shifts between launches.
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
        Color(red: 0.95, green: 0.9, blue: 0.75)
        FallingConfettiView()
    }
    .ignoresSafeArea()
}
