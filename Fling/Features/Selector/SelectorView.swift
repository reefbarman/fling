import SwiftUI

struct SelectorView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var model: SelectorModel

    static let width: CGFloat = 460

    var body: some View {
        Group {
            if let context = coordinator.activeSelectorContext {
                VStack(spacing: 0) {
                    header(context)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 14)

                    if let notice = notice {
                        noticeBanner(notice)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 12)
                    }

                    targetGrid
                        .padding(.horizontal, 14)

                    rememberRow
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 14)

                    Divider().opacity(0.5)

                    footer
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .frame(width: Self.width)
                .sheet(isPresented: $model.isShowingRuleCreation) {
                    RuleCreationSheet(
                        url: context.originalURL,
                        targets: model.targets,
                        defaultTargetID: model.highlightedTarget?.id,
                        onSave: { input in
                            model.isShowingRuleCreation = false
                            coordinator.saveRuleAndOpen(input)
                        },
                        onCancel: {
                            model.isShowingRuleCreation = false
                        }
                    )
                }
            } else {
                Color.clear.frame(width: Self.width, height: 1)
            }
        }
        .background(SelectorBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private func header(_ context: IncomingURLContext) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.originalURL.host(percentEncoded: false) ?? "Link")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(Self.displayPath(for: context.originalURL))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let source = context.sourceApplication {
                    Text("from \(source)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(context.originalURL.absoluteString)

            HStack(spacing: 4) {
                iconButton("doc.on.doc", help: "Copy URL (⌘C)") {
                    coordinator.copyActiveSelectorURL()
                }
                iconButton("xmark", help: "Dismiss and copy URL (Esc)") {
                    model.dismiss()
                }
            }
        }
    }

    private func iconButton(
        _ systemName: String, help: String, isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background(
                    isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Notices

    private var notice: String? {
        if coordinator.isActiveSelectorContextIncognitoUnavailable {
            return
                "⌥ requested Chrome Incognito, but Google Chrome isn't installed. Pick a browser instead."
        }
        if let message = coordinator.lastErrorMessage, !message.isEmpty {
            return message
        }
        return nil
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Targets

    @ViewBuilder
    private var targetGrid: some View {
        let mainTargets = model.mainTargets
        let moreTargets = model.moreTargets
        if mainTargets.isEmpty {
            Text("No browsers configured. Add one in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(spacing: 8) {
                if !moreTargets.isEmpty {
                    HStack {
                        Spacer()
                        moreButton(moreTargets)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, -6)
                }

                LazyVGrid(columns: Self.mainColumns(for: mainTargets.count), spacing: 6) {
                    ForEach(Array(mainTargets.enumerated()), id: \.element.id) { index, target in
                        tile(for: target, at: index, compact: false)
                    }
                }

                if model.isMoreExpanded {
                    moreSection(moreTargets, startingAt: mainTargets.count)
                }
            }
        }
    }

    /// Up to three targets get fixed-width tiles, which the grid centres, so one or two browsers
    /// don't leave an empty slot on the right. Four or more fill the width in rows of four.
    private static func mainColumns(for count: Int) -> [GridItem] {
        if count >= 4 {
            return Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        }
        return Array(repeating: GridItem(.fixed(140), spacing: 6), count: max(count, 1))
    }

    /// Small, quiet toggle above the main icons for targets marked Under More.
    private func moreButton(_ targets: [BrowserTarget]) -> some View {
        let isActive = model.isMoreExpanded
        return Button {
            model.toggleMore()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 16)
                .background(
                    isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(
            isActive
                ? "Hide other browsers (M)"
                : "More browsers: " + targets.map(\.displayName).joined(separator: ", ") + " (M)"
        )
    }

    private func moreSection(_ targets: [BrowserTarget], startingAt offset: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("More")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 0.5)
                Button {
                    model.toggleMore()
                } label: {
                    HStack(spacing: 4) {
                        Text("Show less")
                        KeyCap("M")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            LazyVGrid(
                columns: targets.count >= 5
                    ? Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
                    : Array(repeating: GridItem(.fixed(82), spacing: 4), count: targets.count),
                spacing: 4
            ) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    tile(for: target, at: offset + index, compact: true)
                }
            }
        }
    }

    private func tile(for target: BrowserTarget, at index: Int, compact: Bool) -> some View {
        SelectorTargetTile(
            target: target,
            shortcut: index < 9 ? "\(index + 1)" : nil,
            isHighlighted: index == model.highlightedIndex,
            compact: compact
        ) {
            model.open(target)
        }
        .onHover { hovering in
            if hovering { model.highlightedIndex = index }
        }
    }

    // MARK: - Remember

    private var rememberRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $model.remembersChoice) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(model.rememberedDomain.isEmpty)

            Text("Always open")
                .foregroundStyle(model.remembersChoice ? .primary : .secondary)
                .fixedSize()

            if model.domainCandidates.count > 1 {
                Menu {
                    ForEach(model.domainCandidates, id: \.self) { domain in
                        Button(domain) {
                            model.rememberedDomain = domain
                            model.remembersChoice = true
                        }
                    }
                } label: {
                    Text(model.rememberedDomain)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(model.rememberedDomain)
                    .fontWeight(.semibold)
                    .foregroundStyle(model.remembersChoice ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("here")
                .foregroundStyle(model.remembersChoice ? .primary : .secondary)
                .fixedSize()

            Spacer(minLength: 4)

            KeyCap("R")
        }
        .font(.system(size: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.rememberedDomain.isEmpty { model.remembersChoice.toggle() }
        }
        .help("Save a rule for this domain (and its subdomains) when you choose a browser")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if coordinator.canOpenInChromeIncognito {
                FooterButton(
                    title: coordinator.isActiveSelectorContextForceIncognito
                        ? "Retry Chrome Incognito" : "Open in Chrome Incognito",
                    systemImage: "eye.slash",
                    shortcut: "I"
                ) {
                    model.openInIncognito()
                }
            }

            Spacer()

            FooterButton(title: "Add Rule…", systemImage: "slider.horizontal.3", shortcut: nil) {
                model.isShowingRuleCreation = true
            }

            if coordinator.pendingRequests.count > 0 {
                Text("+\(coordinator.pendingRequests.count) queued")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }

    // MARK: - Helpers

    /// The URL minus scheme and host, so the header doesn't repeat itself.
    static func displayPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: false) { path += "?" + query }
        if let fragment = url.fragment(percentEncoded: false) { path += "#" + fragment }
        return path.isEmpty || path == "/" ? url.absoluteString : path
    }
}

private struct SelectorTargetTile: View {
    let target: BrowserTarget
    let shortcut: String?
    let isHighlighted: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 4 : 6) {
                TargetIconView(target: target)
                    .frame(width: compact ? 34 : 52, height: compact ? 34 : 52)
                    .scaleEffect(isHighlighted ? 1.06 : 1)

                VStack(spacing: 1) {
                    Text(target.displayName)
                        .font(.system(size: compact ? 11 : 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !compact {
                        Text(target.subtitle.isEmpty ? " " : target.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, compact ? 7 : 10)
            .padding(.horizontal, compact ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(alignment: .topTrailing) {
                if let shortcut {
                    KeyCap(shortcut).padding(compact ? 4 : 6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .help(
            target.subtitle.isEmpty
                ? target.displayName : "\(target.displayName) — \(target.subtitle)")
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                if let shortcut { KeyCap(shortcut) }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(isHovering ? 0.09 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 15, minHeight: 15)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            )
    }
}

private struct SelectorBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
