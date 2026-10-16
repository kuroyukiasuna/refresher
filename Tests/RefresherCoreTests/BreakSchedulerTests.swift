import Foundation
import Testing
@testable import RefresherCore

/// Drives a scheduler through simulated time in one-second ticks, like the app does.
private struct Simulation {
    var scheduler: BreakScheduler
    var now = Date(timeIntervalSinceReferenceDate: 0)
    var idleTime: TimeInterval = 0
    var meeting: String?
    var screenLocked = false
    var events: [SchedulerEvent] = []

    init(_ settings: ScheduleSettings) {
        scheduler = BreakScheduler(settings: settings)
        scheduler.tick(conditions)
    }

    var conditions: Conditions {
        Conditions(now: now, idleTime: idleTime, meeting: meeting, screenLocked: screenLocked)
    }

    var startedKinds: [BreakKind] {
        events.compactMap { (event) -> BreakKind? in
            if case let .breakStarted(kind) = event { return kind }
            return nil
        }
    }

    mutating func advance(_ seconds: Int) {
        for _ in 0..<seconds {
            now += 1
            if let event = scheduler.tick(conditions) { events.append(event) }
        }
    }

    /// Jumps ahead without ticking, the way time passes while the Mac sleeps.
    mutating func sleep(_ seconds: TimeInterval) {
        now += seconds
        if let event = scheduler.tick(conditions) { events.append(event) }
    }
}

private func settings(
    work: TimeInterval = 600,
    shortBreak: TimeInterval = 20,
    longEvery: Int? = nil,
    longBreak: TimeInterval = 60,
    headsUp: TimeInterval = 0,
    postpone: TimeInterval = 120,
    away: TimeInterval? = nil
) -> ScheduleSettings {
    ScheduleSettings(
        workInterval: work,
        shortBreakDuration: shortBreak,
        longBreaksEnabled: longEvery != nil,
        longBreakEvery: longEvery ?? 3,
        longBreakDuration: longBreak,
        headsUpLead: headsUp,
        postponeDuration: postpone,
        awayThreshold: away)
}

@Suite struct BreakSchedulerTests {
    @Test func breakStartsWhenTheWorkIntervalIsUp() {
        var sim = Simulation(settings(work: 60, shortBreak: 10))
        sim.advance(59)
        #expect(!sim.scheduler.isOnBreak)
        sim.advance(1)
        #expect(sim.scheduler.phase == .onBreak(.short, remaining: 10, total: 10))
        #expect(sim.events == [.breakStarted(.short)])
    }

    @Test func breakEndsAndTheCountdownStartsOver() {
        var sim = Simulation(settings(work: 60, shortBreak: 10))
        sim.advance(70)
        #expect(sim.scheduler.phase == .working)
        #expect(sim.scheduler.workElapsed == 0)
        #expect(sim.events == [.breakStarted(.short), .breakCompleted])
    }

    @Test func headsUpShowsShortlyBeforeTheBreak() {
        var sim = Simulation(settings(work: 120, headsUp: 30))
        sim.advance(89)
        #expect(!sim.scheduler.isHeadsUp)
        sim.advance(1)
        #expect(sim.scheduler.isHeadsUp)
    }

    @Test func headsUpNeverCoversMoreThanHalfTheInterval() {
        var sim = Simulation(settings(work: 40, headsUp: 30))
        sim.advance(19)
        #expect(!sim.scheduler.isHeadsUp)
        sim.advance(1)
        #expect(sim.scheduler.isHeadsUp)
    }

    @Test func everyThirdBreakIsLong() {
        var sim = Simulation(settings(work: 60, shortBreak: 10, longEvery: 3, longBreak: 30))
        sim.advance(3 * 60 + 2 * 10 + 30)
        #expect(sim.startedKinds == [.short, .short, .long])
        #expect(sim.scheduler.phase == .working)
        #expect(sim.scheduler.nextBreakKind == .short)
    }

    @Test func postponingPushesTheBreakBack() {
        var sim = Simulation(settings(work: 600, headsUp: 30, postpone: 120))
        sim.advance(580)
        sim.scheduler.postpone()
        #expect(sim.scheduler.timeUntilBreak == 120)
        sim.advance(119)
        #expect(!sim.scheduler.isOnBreak)
        sim.advance(1)
        #expect(sim.scheduler.isOnBreak)
    }

    @Test func postponingALongBreakKeepsItLong() {
        var sim = Simulation(settings(work: 60, longEvery: 2))
        sim.scheduler.skipBreak()
        sim.advance(60)
        #expect(sim.scheduler.phase == .onBreak(.long, remaining: 60, total: 60))
        sim.scheduler.postpone()
        #expect(sim.scheduler.nextBreakKind == .long)
    }

    @Test func skippingMovesTheCycleOn() {
        var sim = Simulation(settings(longEvery: 2))
        #expect(sim.scheduler.nextBreakKind == .short)
        sim.scheduler.skipBreak()
        #expect(sim.scheduler.nextBreakKind == .long)
        #expect(sim.events.isEmpty)
    }

    @Test func meetingsPauseTheCountdown() {
        var sim = Simulation(settings(work: 600))
        sim.advance(100)
        sim.meeting = "Zoom meeting"
        sim.advance(3000)
        #expect(sim.scheduler.workElapsed == 100)
        #expect(sim.scheduler.pauseReason == .meeting("Zoom meeting"))
        #expect(!sim.scheduler.isOnBreak)
        sim.meeting = nil
        sim.advance(499)
        #expect(!sim.scheduler.isOnBreak)
        sim.advance(1)
        #expect(sim.scheduler.isOnBreak)
    }

    @Test func meetingStartingMidBreakPutsTheBreakOffUntilAfterIt() {
        var sim = Simulation(settings(work: 600, shortBreak: 20))
        sim.advance(605)
        #expect(sim.scheduler.isOnBreak)
        sim.meeting = "Slack huddle"
        sim.advance(1)
        #expect(!sim.scheduler.isOnBreak)
        #expect(sim.events.last == .breakInterrupted)
        sim.advance(3600)
        #expect(!sim.scheduler.isOnBreak)
        sim.meeting = nil
        sim.advance(Int(BreakScheduler.missedBreakDelay))
        #expect(sim.scheduler.isOnBreak)
    }

    @Test func breakTakenDuringAMeetingIsNotInterrupted() {
        var sim = Simulation(settings(shortBreak: 20))
        sim.meeting = "Teams meeting"
        sim.advance(10)
        sim.scheduler.takeBreak()
        sim.advance(19)
        #expect(sim.scheduler.isOnBreak)
        sim.advance(1)
        #expect(!sim.scheduler.isOnBreak)
    }

    @Test func manualPauseExpires() {
        var sim = Simulation(settings())
        sim.scheduler.pause(until: sim.now + 300)
        sim.advance(299)
        #expect(sim.scheduler.isManuallyPaused)
        #expect(sim.scheduler.workElapsed == 0)
        sim.advance(2)
        #expect(!sim.scheduler.isManuallyPaused)
        #expect(sim.scheduler.workElapsed == 2)
    }

    @Test func pausingEndsABreakInProgress() {
        var sim = Simulation(settings(work: 60))
        sim.advance(65)
        sim.scheduler.pause(until: nil)
        #expect(sim.scheduler.phase == .working)
        sim.advance(3600)
        #expect(sim.scheduler.workElapsed == 0)
        sim.scheduler.resume()
        sim.advance(5)
        #expect(sim.scheduler.workElapsed == 5)
    }

    @Test func timeAwayCountsAsABreak() {
        var sim = Simulation(settings(work: 600, away: 120))
        sim.advance(300)
        for _ in 0..<200 {
            sim.idleTime += 1
            sim.advance(1)
        }
        #expect(sim.scheduler.pauseReason == .away)
        #expect(sim.scheduler.workElapsed == 0)
        sim.idleTime = 0
        sim.advance(10)
        #expect(sim.scheduler.workElapsed == 10)
    }

    @Test func sittingStillInAMeetingIsNotBeingAway() {
        var sim = Simulation(settings(work: 600, away: 120))
        sim.advance(300)
        sim.meeting = "Zoom meeting"
        sim.idleTime = 1000
        sim.advance(10)
        #expect(sim.scheduler.pauseReason == .meeting("Zoom meeting"))
        #expect(sim.scheduler.workElapsed == 300)
    }

    @Test func sleepCountsAsABreak() {
        var sim = Simulation(settings(work: 600))
        sim.advance(300)
        sim.sleep(3600)
        #expect(sim.scheduler.workElapsed == 0)
        #expect(sim.events.isEmpty)
    }

    @Test func breakThatRunsOutDuringSleepEndsQuietly() {
        var sim = Simulation(settings(work: 60, shortBreak: 20))
        sim.advance(65)
        sim.sleep(600)
        #expect(sim.scheduler.phase == .working)
        #expect(sim.events == [.breakStarted(.short)])
    }

    @Test func lockingTheScreenCountsAsABreak() {
        var sim = Simulation(settings(work: 600, shortBreak: 20))
        sim.advance(300)
        sim.screenLocked = true
        sim.advance(60)
        #expect(sim.scheduler.pauseReason == .screenLocked)
        #expect(sim.scheduler.workElapsed == 300)
        sim.screenLocked = false
        sim.advance(1)
        #expect(sim.scheduler.workElapsed == 1)
    }

    @Test func briefLockKeepsTheCountdown() {
        var sim = Simulation(settings(work: 600, shortBreak: 20))
        sim.advance(300)
        sim.screenLocked = true
        sim.advance(5)
        sim.screenLocked = false
        sim.advance(1)
        #expect(sim.scheduler.workElapsed == 301)
    }

    @Test func changingTheIntervalRestartsTheCountdown() {
        var sim = Simulation(settings(work: 600))
        sim.advance(300)
        var changed = sim.scheduler.settings
        changed.workInterval = 200
        sim.scheduler.update(settings: changed)
        sim.advance(1)
        #expect(!sim.scheduler.isOnBreak)
        #expect(sim.scheduler.timeUntilBreak == 199)
    }
}
