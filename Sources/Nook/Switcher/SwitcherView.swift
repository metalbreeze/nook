import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void
    let onBeginRename: (CGSSpaceID) -> Void
    let onFinishRename: (Bool, String) -> Void
    let onClickDesktop: (Int) -> Void
    let onClickApp: (Int) -> Void

    @State private var editName: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var selectedName: String {
        guard model.apps.indices.contains(model.selectedAppIndex) else { return "" }
        return model.apps[model.selectedAppIndex].name
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                desktopRow

                HStack(alignment: .center, spacing: 16) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        appIcon(app, selected: index == model.selectedAppIndex,
                                onClick: { onClickApp(index) })
                    }
                }
                Text(selectedName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Always render the windows row at a stable height so the
                // overlay does not reflow when an app has zero windows or
                // before the first fetch returns — that reflow is the Tab
                // flicker users see. Thumb height ≈ 130 + caption + paddings.
                HStack(spacing: 14) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, win in
                        windowThumb(win, selected: index == model.selectedWindowIndex, index: index)
                    }
                }
                .frame(minHeight: 170)
            }
            .padding(28)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var desktopRow: some View {
        if !model.desktops.isEmpty {
            HStack(spacing: 14) {
                ForEach(Array(model.desktops.enumerated()), id: \.element.id) { idx, desktop in
                    desktopChip(desktop, onClick: { onClickDesktop(idx) })
                }
            }
            .padding(.top, 6)   // leave room above for the rename pencil
        } else {
            legacyNameRow
        }
    }

    /// Fallback row when the chip enumeration returned nothing (degenerate).
    @ViewBuilder
    private var legacyNameRow: some View {
        HStack(spacing: 10) {
            Text(model.desktopName)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func desktopChip(_ desktop: DesktopVM, onClick: @escaping () -> Void) -> some View {
        if model.renamingDesktopID == desktop.id {
            // In-place edit: this chip becomes a small TextField.
            HStack(spacing: 6) {
                Text("\(desktop.index)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                TextField("Name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 180)
                    .focused($nameFieldFocused)
                    .onAppear {
                        editName = desktop.name
                        nameFieldFocused = true
                    }
                    .onSubmit { onFinishRename(true, editName) }
                    .onExitCommand { onFinishRename(false, editName) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        } else {
            // Normal chip with rename button overlaid at the upper-left.
            Text(desktop.label)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(desktop.isReal ? Color.white.opacity(0.25) : Color.clear)
                .overlay(
                    Capsule()
                        .stroke(desktop.isPreviewed ? Color.white.opacity(0.7) : Color.clear,
                                lineWidth: 1.5)
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
                .onTapGesture { if !desktop.isReal { onClick() } }
                .overlay(alignment: .topTrailing) {
                    Button(action: { onBeginRename(desktop.id) }) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.8))
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Rename desktop")
                    .offset(x: 6, y: -6)
                }
        }
    }

    @ViewBuilder
    private func appIcon(_ app: SwitcherApp, selected: Bool, onClick: @escaping () -> Void) -> some View {
        // Parked apps (Cmd+H or window-less) render one size smaller, faint bg,
        // lower opacity, with a window-count badge — they read as "parked,
        // click to restore" and Tab skips them.
        let iconSize: CGFloat = app.isParked ? 40 : 64
        let pad: CGFloat = app.isParked ? 8 : 10
        let background: Color = app.isParked
            ? Color.white.opacity(0.08)
            : (selected ? Color.white.opacity(0.25) : Color.clear)
        Group {
            if let image = app.icon {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.white)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .padding(pad)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(app.isParked ? 0.55 : 1.0)
        .overlay(alignment: .topTrailing) {
            if app.isParked {
                Text("\(app.windowCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Color.black.opacity(0.8)))
                    .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
    }

    private func numberedTitle(_ win: SwitcherWindow, index: Int) -> String {
        let base = win.title.isEmpty ? "Untitled" : win.title
        return index < 9 ? "\(index + 1)  \(base)" : base
    }

    @ViewBuilder
    private func windowThumb(_ win: SwitcherWindow, selected: Bool, index: Int) -> some View {
        let thumbW: CGFloat = win.isMinimized ? 130 : 200
        let thumbH: CGFloat = win.isMinimized ? 85 : 130
        VStack(spacing: 6) {
            Group {
                if let image = win.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(win.isMinimized ? 0.5 : 0.3))
                        .overlay(Image(systemName: win.isMinimized ? "macwindow.badge.minus" : "macwindow")
                            .foregroundStyle(.white))
                }
            }
            .frame(width: thumbW, height: thumbH)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(numberedTitle(win, index: index))
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: thumbW)
        }
        .padding(8)
        .background(selected ? Color.white.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering in if hovering { onHoverWindow(index) } }
        .onTapGesture { onClickWindow(index) }
    }
}
