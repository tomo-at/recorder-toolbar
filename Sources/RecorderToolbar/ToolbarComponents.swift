import SwiftUI
import AVFoundation

// MARK: – Shared toolbar components
// Used across V1–V5, Horizontal, Compact, and Upload mode.

struct CloseSection<Icon: View>: View {
    let action: () -> Void
    let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.16))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
        }
    }
}

struct SegmentButton: View {
    let icon:        String
    let label:       String
    var iconColor:   Color = .white
    var isActive:    Bool  = false
    var isDisabled:  Bool  = false
    var showBadge:   Bool  = false
    var badgeColor:  Color = .modelessTeal
    let action:      () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 20, height: 20)
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -1)
                        }
                    }
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color.contentTertiary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 48)
            .background(isActive ? Color.white.opacity(0.16) : (hovering && !isDisabled ? Color.highlightPrimary : .clear))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
    }
}

// MARK: – Upload progress bar

/// Thin progress bar shown above the toolbar during uploads. height: 4 for V1, 2 for V5.
struct UploadProgressBarView: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.modelessBlack24)
                Rectangle().fill(Color.modelessTeal)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
            }
        }
        .frame(height: height)
    }
}

struct ToolbarDivider: View {
    var height: CGFloat = 32

    var body: some View {
        Rectangle()
            .fill(Color.highlightPrimary)
            .frame(width: 1, height: height)
            .padding(.horizontal, 4)
    }
}

/// Thin header bar shown above toolbar controls (V4 / V5 message / upload mode).
struct ToolbarHeader: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.60))
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .background(Color.black.opacity(0.24))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.highlightPrimary)
                    .frame(height: 0.5)
            }
    }
}

// ── Shortcut tooltip view (shown above type-select buttons) ──

struct ShortcutTooltipView: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white)
            Text(shortcut)
                .font(.system(size: 12))
                .foregroundColor(Color.subtitleGray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bgTooltip)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        .padding(7)
    }
}
