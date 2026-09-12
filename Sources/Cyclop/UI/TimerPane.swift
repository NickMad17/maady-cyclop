import SwiftUI

struct TimerPane: View {
    @ObservedObject var timer: TimerStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.isFinished ? localized("Done") : timer.clock)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(Theme.contentAnimation, value: timer.secondsLeft)
                    .animation(Theme.contentAnimation, value: timer.isFinished)

                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 4)

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    TimerField(
                        value: timer.hours,
                        unit: localized("h"),
                        onMinus: { timer.bumpHours(-1) },
                        onPlus: { timer.bumpHours(1) }
                    )
                    TimerField(
                        value: timer.minutes,
                        unit: localized("min"),
                        onMinus: { timer.bumpMinutes(-1) },
                        onPlus: { timer.bumpMinutes(1) }
                    )
                }
                .padding(.top, 4)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button { timer.toggle() } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(NotchButtonStyle(size: 36, prominent: true))
                    .help(localized(timer.isRunning ? "Pause" : "Start"))

                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(NotchButtonStyle(size: 30))
                    .opacity(timer.isRunning || timer.remaining < timer.duration || timer.isFinished ? 1 : 0.35)
                    .disabled(!timer.isRunning && timer.remaining >= timer.duration && !timer.isFinished)
                    .help(localized("Reset"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                ForEach(TimerStore.presets, id: \.self) { interval in
                    Button { timer.start(interval) } label: {
                        Text(localized("%d min", Int(interval / 60)))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(selected(interval) ? .white : Theme.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selected(interval) ? Theme.surfaceHover : Theme.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var status: String {
        if timer.isFinished { return localized("Timer finished") }
        if timer.isRunning { return localized("The bar fills under the notch") }
        if timer.remaining > 0, timer.remaining < timer.duration { return localized("Paused") }
        return localized("Then a red bar fills under the notch")
    }

    private func selected(_ interval: TimeInterval) -> Bool {
        abs(timer.duration - interval) < 0.5
    }
}

private struct TimerField: View {
    let value: Int
    let unit: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 28)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            HStack(spacing: 4) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 18, height: 16)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.surface))
                }
                .buttonStyle(.plain)
                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 18, height: 16)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.surface))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Straight track under the folded notch — the bottom edge only, not the
/// shoulders. One point of air so it reads as a line, not a chin.
struct TimerNotchBar: View {
    @ObservedObject var timer: TimerStore
    @State private var flash = false

    private let red = Color(red: 1.00, green: 0.22, blue: 0.20)
    private let thickness: CGFloat = 2

    var body: some View {
        if timer.showsInNotch {
            Capsule()
                .fill(red.opacity(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(red)
                            .frame(width: max(thickness, geo.size.width * timer.elapsed))
                            .shadow(color: red.opacity(timer.isFinished ? 0.95 : 0.65), radius: timer.isFinished ? 6 : 2)
                    }
                }
                .frame(height: thickness)
                .opacity(timer.isFinished && flash ? 0.3 : 1)
                .allowsHitTesting(false)
                .onAppear { flash = timer.isFinished }
                .onChange(of: timer.isFinished) { _, done in
                    flash = done
                }
                .animation(
                    timer.isFinished
                        ? .easeInOut(duration: 0.38).repeatForever(autoreverses: true)
                        : .linear(duration: 0.05),
                    value: flash
                )
                .animation(.linear(duration: 0.05), value: timer.elapsed)
        }
    }
}
