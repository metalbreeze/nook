import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onHoverWindow: (Int) -> Void
    let onClickWindow: (Int) -> Void
    let onBeginRename: () -> Void
    let onFinishRename: (Bool, String) -> Void

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
                nameRow

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
    private var nameRow: some View {
        if model.isRenaming {
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
        } else {
            HStack(spacing: 10) {
                Text(model.desktopName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Button("Rename") { onBeginRename() }
                    .buttonStyle(.bordered)
            }
        }
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
