import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private var selectedName: String {
        guard model.apps.indices.contains(model.selectedAppIndex) else { return "" }
        return model.apps[model.selectedAppIndex].name
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        icon(for: app, selected: index == model.selectedAppIndex)
                    }
                }
                Text(selectedName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(28)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func icon(for app: SwitcherApp, selected: Bool) -> some View {
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
}
