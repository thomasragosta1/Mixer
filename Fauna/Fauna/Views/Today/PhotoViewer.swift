import SwiftUI

/// Full-screen photo with pinch and double-tap zoom, panning, and swipe down to close.
struct PhotoViewer: View {
    let animal: Animal
    let preview: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0
    @State private var chromeVisible = true

    var body: some View {
        ZStack {
            Color.black
                .opacity(Double(1 - min(0.6, abs(dismissDrag) / 400)))
                .ignoresSafeArea()

            if let shown = image ?? preview {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dismissDrag)
                    .gesture(zoom.simultaneously(with: pan))
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } }
                    .accessibilityLabel("Photo of the \(animal.name)")
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            if chromeVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(animal.name)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                        Text(animal.scientificName)
                            .font(.subheadline.italic())
                            .foregroundStyle(.white.opacity(0.7))
                        PhotoCreditLine(animal: animal, onDark: true)
                            .padding(.top, 2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .task {
            // Start with the header photo, then swap in a sharper one.
            if let sharp = await WikiImages.shared.image(for: animal.wikipediaTitle, size: .full) {
                image = sharp
            }
        }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(5, max(1, lastScale * value.magnification)) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { withAnimation(.spring) { resetZoom() } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                } else {
                    dismissDrag = value.translation.height
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                    dismiss()
                } else {
                    withAnimation(.spring) { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if scale > 1 { resetZoom() } else { scale = 2.5; lastScale = 2.5 }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
