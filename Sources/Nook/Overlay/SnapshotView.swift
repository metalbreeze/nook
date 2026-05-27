import SwiftUI

struct SnapshotView: View {
    let appName: String
    let thumbnails: [WindowThumbnail]
    let onSelect: (WindowThumbnail) -> Void
    let onDismiss: () -> Void

    private let cellWidth: CGFloat = 320
    private let gridSpacing: CGFloat = 28

    private var columnCount: Int {
        min(max(thumbnails.count, 1), 4)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: gridSpacing), count: columnCount)
    }

    /// Intrinsic width of the grid so it forms a centered cluster instead of
    /// stretching edge-to-edge.
    private var gridWidth: CGFloat {
        CGFloat(columnCount) * cellWidth + CGFloat(columnCount - 1) * gridSpacing
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    Text("\(appName) — \(thumbnails.count) window\(thumbnails.count == 1 ? "" : "s")")
                        .font(.title2).bold()
                        .foregroundStyle(.white)

                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(thumbnails) { thumb in
                            Button { onSelect(thumb) } label: {
                                cell(thumb)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: gridWidth)
                }
                // Fill the viewport and center the content; grow + scroll when
                // there are too many windows to fit.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
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
                    .frame(maxWidth: cellWidth, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: cellWidth, height: 220)
                    .overlay(Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.white))
            }
            Text(thumb.title.isEmpty ? appName : thumb.title)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: cellWidth - 20)
        }
    }
}
