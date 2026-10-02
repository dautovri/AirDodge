import Foundation
import CoreGraphics

// OpponentDefinition — the data-driven shape of a fight.
//
// Per /plan-eng-review Issue 1 (locked decision): extract opponent data into
// a struct. Don't build a `DodgeEvent` protocol abstraction yet — the engine
// stays boxing-specific until skin #2 actually exists.
//
// To add an opponent: append a new static factory below. ~10 lines per
// opponent once the pattern is established.

struct OpponentDefinition {
    let id: String                     // matches sprite atlas + audio file basename
    let name: String                   // e.g. "VITRINE BLOOM"
    let country: String                // e.g. "PARIS"
    let record: String                 // e.g. "0-99"
    let pepTalks: [String]             // shown between rounds, randomly selected
    let punches: [PunchType]           // patterns this opponent throws
    let telegraphSec: TimeInterval     // wind-up duration
    let restSec: TimeInterval          // gap between punches
    let initialHP: Int                 // player HP for this fight (Sandbag is special)
    let opponentHP: Int                // opponent HP — number of dodges to KO them
    let musicTrack: String?            // bundle filename (no ext); nil = no music
    let isTutorial: Bool               // signals every tell verbally; can't lose
    let bossRank: Int                  // ordering: 0=tutorial, 1=mid, 99=final boss

    /// Sandbag and Vitrine Bloom are free; everyone above them needs the
    /// Full Fight Card unlock.
    var requiresUnlock: Bool { bossRank > 1 }
}

extension OpponentDefinition {

    // MARK: - Roster (3 opponents per CEO plan)

    static let sandbag = OpponentDefinition(
        id: "sandbag",
        name: "SANDBAG",
        // Was "TRAINING", which duplicated the difficulty badge above it and
        // made the card read as a rendering bug next to PARIS / STATEVILLE.
        country: "THE GYM",
        record: "0-0",
        pepTalks: [
            "Tip: tilt your HEAD, not your phone.",
            "Don't worry about losing. You can't.",
            "Just feel the rhythm. Slip, duck, slip.",
        ],
        punches: [.leftHook, .rightHook, .uppercut, .jab],
        telegraphSec: 2.2,        // extra-slow for first-time learners
        restSec: 1.6,             // breathing room between punches
        initialHP: 999,           // can't lose
        opponentHP: 5,            // 5 successful dodges to win the tutorial
        musicTrack: "sandbag_loop",
        isTutorial: true,
        bossRank: 0
    )

    static let vitrineBloom = OpponentDefinition(
        id: "vitrine_bloom",
        name: "VITRINE BLOOM",
        country: "PARIS",
        record: "0-99",
        pepTalks: [
            "He's a glass cannon. One clean hit and he wobbles.",
            "Watch his shoulders — they tell you which way the hook's coming.",
            "Stay loose. Don't tense up. He's more nervous than you.",
            "He hasn't won a fight since 1987. Don't be his comeback story.",
        ],
        punches: [.leftHook, .rightHook, .jab],
        telegraphSec: 1.6,        // standard
        restSec: 1.2,
        initialHP: 5,
        opponentHP: 8,
        musicTrack: "vitrine_bloom_loop",
        isTutorial: false,
        bossRank: 1
    )

    static let theWarden = OpponentDefinition(
        id: "the_warden",
        name: "THE WARDEN",
        country: "STATEVILLE",
        record: "47-1",
        pepTalks: [
            "He's a finisher. Don't get cocky.",
            "He throws three punches in the same rhythm — then breaks it on four.",
            "If you see his eyes glow, the next telegraph is half as long.",
            "Last guy he fought is still in the ring. Don't be the next one.",
        ],
        punches: [.leftHook, .rightHook, .jab, .uppercut],
        telegraphSec: 1.0,        // near input-pipeline floor (~700ms minimum)
        restSec: 0.85,
        initialHP: 5,
        opponentHP: 12,
        musicTrack: "the_warden_loop",
        isTutorial: false,
        bossRank: 99
    )

    /// Roster ordered by bossRank. Used by the menu to show progression.
    static let allOpponents: [OpponentDefinition] = [
        .sandbag,
        .vitrineBloom,
        .theWarden,
    ]
}
