import AppKit
import Foundation

/// A countdown that lives under the notch, including while the panel is folded.
///
/// Everything else in the panel answers a hover. This one has to keep ticking
/// after the pointer leaves: a pomodoro that paused when you went back to
/// work would be a timer that timed the panel, not the work. The folded notch
/// stays the same shape it always was; a red bar under it is the display.
@MainActor
final class TimerStore: ObservableObject {
    /// Presets a sitting session actually uses. 25 is the pomodoro; 15 is the
    /// one people reach for without naming a method. Longer sits go through
    /// the hours field, not through another chip.
    static let presets: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60, 25 * 60, 45 * 60]

    @Published private(set) var remaining: TimeInterval
    @Published private(set) var duration: TimeInterval
    @Published private(set) var isRunning = false
    /// True for a few seconds after zero, so the bar can flash at the edge
    /// without stealing focus to say it is done.
    @Published private(set) var isFinished = false
    @Published private(set) var hours: Int
    @Published private(set) var minutes: Int

    /// Raised the moment a countdown starts, so the panel that was just used
    /// to start it can fold itself. The pointer is still on it; folding is
    /// the point, not a side effect of walking away.
    var onStarted: (() -> Void)?

    private var tick: Timer?
    private var deadline: Date?
    private var finishWork: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    private static let lastKey = "timer.lastDuration"

    init() {
        let last = defaults.object(forKey: Self.lastKey) as? Double ?? 15 * 60
        let duration = last > 0 ? last : 15 * 60
        self.duration = duration
        self.remaining = duration
        self.hours = min(23, Int(duration) / 3600)
        self.minutes = (Int(duration) % 3600) / 60
    }

    /// Whether the folded notch should draw the bar.
    var showsInNotch: Bool { isRunning || isFinished }

    /// How far the red bar has travelled, 0 → 1. The edge of the notch is
    /// the end of the sit: that is the signal, not a number in the cutout.
    var elapsed: Double {
        guard duration > 0 else { return 0 }
        if isFinished { return 1 }
        return max(0, min(1, 1 - remaining / duration))
    }

    /// Whole seconds left, rounded up so 0:01 is still on screen until the
    /// last instant, rather than jumping to 0:00 a second early.
    var secondsLeft: Int { max(0, Int(remaining.rounded(.up))) }

    var clock: String {
        let total = isFinished ? 0 : secondsLeft
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var customDuration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60)
    }

    func start(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        finishWork?.cancel()
        duration = interval
        remaining = interval
        hours = min(23, Int(interval) / 3600)
        minutes = (Int(interval) % 3600) / 60
        deadline = Date().addingTimeInterval(interval)
        isFinished = false
        isRunning = true
        defaults.set(interval, forKey: Self.lastKey)
        arm()
        onStarted?()
    }

    func startCustom() {
        start(customDuration)
    }

    func bumpHours(_ delta: Int) {
        hours = min(23, max(0, hours + delta))
        persistCustom()
    }

    func bumpMinutes(_ delta: Int) {
        var nextHours = hours
        var nextMinutes = minutes + delta
        if nextMinutes >= 60 {
            nextHours = min(23, nextHours + 1)
            nextMinutes = nextHours == 23 && minutes + delta >= 60 ? 59 : nextMinutes % 60
        } else if nextMinutes < 0 {
            if nextHours == 0 {
                nextMinutes = 0
            } else {
                nextHours -= 1
                nextMinutes = 59
            }
        }
        hours = nextHours
        minutes = nextMinutes
        persistCustom()
    }

    func pause() {
        guard isRunning else { return }
        remaining = max(0, deadline?.timeIntervalSinceNow ?? remaining)
        isRunning = false
        deadline = nil
        tick?.invalidate()
        tick = nil
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        isFinished = false
        deadline = Date().addingTimeInterval(remaining)
        isRunning = true
        arm()
    }

    func reset() {
        finishWork?.cancel()
        tick?.invalidate()
        tick = nil
        deadline = nil
        isRunning = false
        isFinished = false
        remaining = duration
    }

    func toggle() {
        if isRunning {
            pause()
        } else if remaining > 0, remaining < duration {
            resume()
        } else {
            start(duration)
        }
    }

    private func persistCustom() {
        let interval = customDuration
        if interval > 0 { defaults.set(interval, forKey: Self.lastKey) }
        if !isRunning, !isFinished, interval > 0 {
            duration = interval
            remaining = interval
        }
    }

    private func arm() {
        tick?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulse() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func pulse() {
        guard let deadline else { return }
        let left = deadline.timeIntervalSinceNow
        if left <= 0 {
            finish()
            return
        }
        remaining = left
    }

    private func finish() {
        tick?.invalidate()
        tick = nil
        deadline = nil
        remaining = 0
        isRunning = false
        isFinished = true
        // A sound, not a banner: a notification would be a permission, and
        // Cyclop already spent its one on Calendar. The bar is on screen
        // either way; the chime is for ears that were not looking up.
        NSSound(named: "Glass")?.play()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isFinished, !self.isRunning else { return }
            self.isFinished = false
            self.remaining = self.duration
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
