import SwiftUI

/// Title, one-line explanation and trailing actions at the top of each settings page.
struct SettingsPaneHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                actions()
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

extension SettingsPaneHeader where Actions == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() })
    }
}

/// Compact search box. `.searchable` needs a SwiftUI-managed toolbar, which this AppKit-hosted
/// window doesn't have.
struct SettingsSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 200)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct TargetIconView: View {
    let target: BrowserTarget

    var body: some View {
        TargetIconImage(icon: target.customIcon, appIcon: target.appIcon)
    }
}

/// A custom icon with a small browser badge in the corner, or just the browser icon.
struct TargetIconImage: View {
    let icon: NSImage?
    let appIcon: NSImage?

    var body: some View {
        if let icon {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                // Match the macOS app icon grid: an 824/1024 tile with ~22.5% continuous corners,
                // so custom icons sit at the same size and shape as Safari or Chrome.
                let tile = side * 0.805
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: tile, height: tile)
                    .clipShape(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: side * 0.02, y: side * 0.01)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let side = geometry.size.width * 0.42
                    if let appIcon, geometry.size.width >= 24 {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: side, height: side)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .bottomTrailing
                            )
                            .offset(x: side * 0.08, y: side * 0.08)
                    }
                }
            }
        } else if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Small "icon + name" pill showing where a rule sends links.
struct TargetChip: View {
    let target: BrowserTarget?

    var body: some View {
        HStack(spacing: 5) {
            if let target {
                TargetIconView(target: target)
                    .frame(width: 16, height: 16)
                Text(target.displayName)
                    .lineLimit(1)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Missing target")
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .help(target.map { "Opens in \($0.displayName)" } ?? "The target for this rule was deleted")
    }
}

/// Edit/delete buttons that only show while the row is hovered, so the list stays calm.
struct RowHoverActions: View {
    let isVisible: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .help("Edit")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}
