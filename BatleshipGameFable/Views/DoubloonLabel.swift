import SwiftUI

/// A doubloon icon with an amount — the game's currency, styled as pirate treasure.
struct DoubloonLabel: View {
    let amount: Int
    var fontSize: CGFloat = 18
    var prefix: String = ""

    var body: some View {
        HStack(spacing: fontSize * 0.3) {
            Image("coin_doubloon")
                .resizable()
                .scaledToFit()
                .frame(width: fontSize * 1.25, height: fontSize * 1.25)
            Text("\(prefix)\(amount.formatted())")
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(amount) doubloons")
    }
}

#Preview {
    VStack(spacing: 12) {
        DoubloonLabel(amount: 1205)
        DoubloonLabel(amount: 280, fontSize: 34, prefix: "+")
            .foregroundStyle(.yellow)
    }
    .padding()
    .background(Color.blue)
}
