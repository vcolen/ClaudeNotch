import Testing
@testable import ClaudeNotch

@Suite("Animation Tokens")
struct AnimationTokenTests {

    @Test("staggerDelay returns 0 for single item")
    func staggerDelaySingleItem() {
        #expect(NotchTokens.Animation.staggerDelay(index: 0, total: 1) == 0)
    }

    @Test("staggerDelay returns 0 for first item in group")
    func staggerDelayFirstItem() {
        #expect(NotchTokens.Animation.staggerDelay(index: 0, total: 5) == 0)
    }

    @Test("staggerDelay total never exceeds 250ms")
    func staggerDelayMaxCap() {
        let lastDelay = NotchTokens.Animation.staggerDelay(index: 99, total: 100)
        #expect(lastDelay <= 0.25)
    }

    @Test("staggerDelay is monotonically increasing")
    func staggerDelayMonotonic() {
        let total = 10
        for i in 1..<total {
            let prev = NotchTokens.Animation.staggerDelay(index: i - 1, total: total)
            let curr = NotchTokens.Animation.staggerDelay(index: i, total: total)
            #expect(curr > prev)
        }
    }

    @Test("Pulse duration tokens are positive")
    func pulseDurationsPositive() {
        #expect(NotchTokens.Animation.workingPulseDuration > 0)
        #expect(NotchTokens.Animation.attentionPulseDuration > 0)
    }

    @Test("Attention pulse is slower than working pulse")
    func attentionSlowerThanWorking() {
        #expect(NotchTokens.Animation.attentionPulseDuration > NotchTokens.Animation.workingPulseDuration)
    }

    @Test("Frame duration matches expand spring response order of magnitude")
    func frameDurationReasonable() {
        #expect(NotchTokens.Animation.frameDuration > 0.1)
        #expect(NotchTokens.Animation.frameDuration < 2.0)
    }

    @Test("Selection flash sequence: fadeIn is shortest, fadeOut is intermediate, flash is longest")
    func selectionFlashOrdering() {
        #expect(NotchTokens.Animation.selectionFadeIn < NotchTokens.Animation.selectionFadeOut)
        #expect(NotchTokens.Animation.selectionFadeOut < NotchTokens.Animation.selectionFlashDuration)
    }

    @Test("staggerDelay returns 0 for total of 0")
    func staggerDelayZeroTotal() {
        #expect(NotchTokens.Animation.staggerDelay(index: 0, total: 0) == 0)
    }

    @Test("staggerDelay clamps index to total - 1")
    func staggerDelayIndexExceedsTotal() {
        let delay = NotchTokens.Animation.staggerDelay(index: 10, total: 5)
        #expect(delay <= 0.25)
    }

    @Test("staggerDelay returns 0 for negative index")
    func staggerDelayNegativeIndex() {
        #expect(NotchTokens.Animation.staggerDelay(index: -1, total: 5) == 0)
    }
}

@Suite("NSAnimationHelper")
struct NSAnimationHelperTests {

    @Test("Sync animate calls body exactly once")
    @MainActor func syncAnimateCallsBody() {
        var callCount = 0
        NSAnimationHelper.animate(duration: 0) {
            callCount += 1
        }
        #expect(callCount == 1)
    }

    @Test("Async animate calls body exactly once")
    @MainActor func asyncAnimateCallsBody() async {
        nonisolated(unsafe) var callCount = 0
        await NSAnimationHelper.animate(duration: 0) {
            callCount += 1
        }
        #expect(callCount == 1)
    }
}

@Suite("Animation State Transitions")
struct AnimationStateTransitionTests {

    @Test("Working to waitingInput sets needsInput attention")
    @MainActor func workingToWaitingSetsAttention() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput)
        #expect(instance.attentionType == .needsInput)
        #expect(instance.needsAttention == true)
    }

    @Test("Working to idle sets taskFinished attention")
    @MainActor func workingToIdleSetsTaskFinished() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .idle)
        #expect(instance.attentionType == .taskFinished)
    }

    @Test("Transition to working clears attention")
    @MainActor func transitionToWorkingClearsAttention() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput)
        instance.transition(to: .working)
        #expect(instance.attentionType == nil)
        #expect(instance.needsAttention == false)
    }

    @Test("clearAttention removes attention state")
    @MainActor func clearAttentionRemovesState() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput)
        instance.clearAttention()
        #expect(instance.attentionType == nil)
        #expect(instance.attentionSetAt == nil)
    }

    @Test("Attention persists across non-working transitions")
    @MainActor func attentionPersistsAcrossNonWorking() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput)
        #expect(instance.attentionType == .needsInput)
        instance.transition(to: .idle)
        #expect(instance.attentionType == .needsInput) // persists
    }
}
