import SwiftUI

struct ColorPickerPane: View {
    @ObservedObject var picker: ColorPickerStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                if let current = picker.current {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(current.color)
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )

                    Text(current.hex)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 10)

                    Text(picker.justCopied ? localized("Copied") : localized("On the pasteboard"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(picker.justCopied ? Color.green.opacity(0.85) : Theme.secondary)
                        .padding(.top, 3)
                        .animation(Theme.contentAnimation, value: picker.justCopied)
                } else {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Text("Click the dropper, then a pixel.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 8)
                }

                Spacer(minLength: 10)

                Button { picker.pick() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: picker.justCopied ? "checkmark" : "eyedropper")
                            .font(.system(size: 10, weight: .semibold))
                        Text(localized("Pick"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.surfaceHover))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !picker.recents.isEmpty {
                VStack(alignment: .trailing, spacing: 7) {
                    ForEach(picker.recents) { swatch in
                        Button { picker.copy(swatch) } label: {
                            HStack(spacing: 8) {
                                Text(swatch.hex)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                                Circle()
                                    .fill(swatch.color)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(localized("Copy"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 4)
    }
}
