import SwiftUI

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(String, String, String)] = [
        ("arrow.left.and.right", String(localized: "Tilt left or right"), String(localized: "Slip hooks. The banner tells you which way.")),
        ("arrow.down", String(localized: "Duck"), String(localized: "Nod your head down to get under uppercuts.")),
        ("bolt.fill", String(localized: "Jabs"), String(localized: "Slip to either side.")),
        ("trophy.fill", String(localized: "Counter-punch"), String(localized: "Every slip lands a counter. Empty their bar to win; take five hits and you're down.")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DodgeDemoView()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 18))

                    ForEach(rules, id: \.1) { symbol, title, detail in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: symbol)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.headline).foregroundStyle(.white)
                                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }

                    Text("Works with \(MotionManager.Status.supportedHeadphones). No compatible headphones? Turn on Touch controls in Settings: hold the left or right side of the screen to slip, the middle to duck.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea())
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }
}
