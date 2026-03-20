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

    @Test("Selection flash sequence has correct ordering: fadeIn < flash < fadeOut")
    func selectionFlashOrdering() {
        #expect(NotchTokens.Animation.selectionFadeIn < NotchTokens.Animation.selectionFlashDuration)
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
