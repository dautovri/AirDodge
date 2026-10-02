import AVFoundation
import SwiftUI
import UIKit

/// Muted, looping clip of someone slipping and ducking pixel punches.
struct HowToPlayVideo: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: "how_to_play", withExtension: "mp4") else { return view }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Never take the audio session from the player's own music.
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

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
                    HowToPlayVideo()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 18))
                        .accessibilityLabel("Video: a player tilts and ducks their head to dodge punches")

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

                    Text("Works with \(MotionManager.Status.supportedHeadphones). Your head is the controller — there are no touch controls.")
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
