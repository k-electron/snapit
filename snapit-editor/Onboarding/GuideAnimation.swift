import Observation
import SwiftUI

/// The Permission guide's cursor animation: a few loops of one finite SwiftUI animation, then it
/// stops and the drawing rests on its last pose. Nothing runs when it is not playing: no timer, no
/// display link, no repeat-forever animation, so a window that sits idle or hidden costs 0% CPU.
///
/// `progress` only ever grows. A play animates it by `loops`; stopping sets it to the next whole
/// number without animation, which ends an animation in flight. The drawing reads the fraction of
/// `progress` as the position in one loop, so no reset to 0 is ever needed (a reset straight
/// followed by a new animation would be merged by SwiftUI into no animation at all).
@MainActor
@Observable
final class GuideAnimation {
    enum State: String {
        /// Not playing and not run to the end: the guide is hidden, or not showing this animation.
        case idle
        case playing
        /// Played its loops to the end.
        case stopped
    }

    static let loops = 3
    static let loopSeconds = 3.0

    private(set) var progress = 0.0
    private(set) var state = State.idle
    /// How many times it has started.
    private(set) var plays = 0
    /// Changes whenever the animation is stopped. The drawing is given this as its identity: SwiftUI
    /// keeps evaluating an animation it was running for the rest of its duration even after the value
    /// was set again, and a drawing with a new identity starts from nothing.
    private(set) var epoch = 0
    @ObservationIgnored private var generation = 0

    /// Plays `loops` loops from the start, unless it is playing already.
    func play() {
        guard state != .playing else { return }
        generation += 1
        let mine = generation
        state = .playing
        plays += 1
        withAnimation(.linear(duration: Self.loopSeconds * Double(Self.loops)), completionCriteria: .logicallyComplete) {
            progress += Double(Self.loops)
        } completion: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.state = .stopped
        }
    }

    /// Ends the animation now (the guide is hidden, or left): the drawing goes back to its first
    /// pose and the next `play()` starts from there.
    func stop() {
        guard state != .idle else { return }
        generation += 1
        state = .idle
        epoch += 1
        withAnimation(nil) { progress = progress.rounded(.up) + 1 }
    }
}
