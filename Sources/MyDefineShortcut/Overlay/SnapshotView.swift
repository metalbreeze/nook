import SwiftUI

struct SnapshotView: View {
    let appName: String
    let thumbnails: [WindowThumbnail]
    let onSelect: (WindowThumbnail) -> Void
    let onDismiss: () -> Void

    private var columns: [GridItem] {
        let count = min(max(thumbnails.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: count)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text("\(appName) — \(thumbnails.count) window\(thumbnails.count == 1 ? "" : "s")")
                    .font(.title2).bold()
                    .foregroundStyle(.white)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(thumbnails) { thumb in
                            Button { onSelect(thumb) } label: {
                                cell(thumb)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cell(_ thumb: WindowThumbnail) -> some View {
        VStack(spacing: 8) {
            if let image = thumb.image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 320, height: 220)
                    .overlay(Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.white))
            }
            Text(thumb.title.isEmpty ? appName : thumb.title)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 300)
        }
    }
}
