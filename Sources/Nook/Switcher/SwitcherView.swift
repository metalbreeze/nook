import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void
    let onBeginRename: () -> Void
    let onFinishRename: (Bool, String) -> Void
    let onClickDesktop: (Int) -> Void

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

                HStack(spacing: 16) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        appIcon(app, selected: index == model.selectedAppIndex)
                    }
                }
                Text(selectedName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !model.windows.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, win in
                            windowThumb(win, selected: index == model.selectedWindowIndex, index: index)
                        }
                    }
                }
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
        if model.isRenaming {
            renameField
        } else if model.desktops.count >= 2 {
            HStack(spacing: 10) {
                ForEach(Array(model.desktops.enumerated()), id: \.element.id) { idx, desktop in
                    desktopChip(desktop, onClick: { onClickDesktop(idx) })
                    if desktop.isCurrent {
                        Button("Rename") { onBeginRename() }
                            .buttonStyle(.bordered)
                    }
                }
            }
        } else {
            legacyNameRow
        }
    }

    @ViewBuilder
    private var legacyNameRow: some View {
        HStack(spacing: 10) {
            Text(model.desktopName)
                .font(.headline)
                .foregroundStyle(.white)
            Button("Rename") { onBeginRename() }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var renameField: some View {
        TextField("Desktop name", text: $editName)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
            .focused($nameFieldFocused)
            .onAppear {
                editName = model.desktopName
                nameFieldFocused = true
            }
            .onSubmit { onFinishRename(true, editName) }
            .onExitCommand { onFinishRename(false, editName) }
    }

    @ViewBuilder
    private func desktopChip(_ desktop: DesktopVM, onClick: @escaping () -> Void) -> some View {
        Text(desktop.label)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(desktop.isCurrent ? Color.white.opacity(0.25) : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onHover { hovering in
                // The current chip stays at its highlight; non-current chips
                // get no hover affordance to keep the row visually calm
                // (window thumbs already provide hover feedback elsewhere).
                _ = hovering
            }
            .onTapGesture { if !desktop.isCurrent { onClick() } }
    }

    @ViewBuilder
    private func appIcon(_ app: SwitcherApp, selected: Bool) -> some View {
        Group {
            if let image = app.icon {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .padding(10)
        .background(selected ? Color.white.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func numberedTitle(_ win: SwitcherWindow, index: Int) -> String {
        let base = win.title.isEmpty ? "Untitled" : win.title
        return index < 9 ? "\(index + 1)  \(base)" : base
    }

    @ViewBuilder
    private func windowThumb(_ win: SwitcherWindow, selected: Bool, index: Int) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image = win.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.gray.opacity(0.3))
                        .overlay(Image(systemName: "macwindow").foregroundStyle(.white))
                }
            }
            .frame(width: 200, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(numberedTitle(win, index: index))
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 200)
        }
        .padding(8)
        .background(selected ? Color.white.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering in if hovering { onHoverWindow(index) } }
        .onTapGesture { onClickWindow(index) }
    }
}
