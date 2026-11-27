import SwiftUI

/// "How big is it?": the animal's silhouette, cut from its own photo, beside something
/// familiar of known size. Lengths are drawn to scale; weights as a count of the familiar thing.
struct SizeComparisonView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let animal: Animal
    let comparison: SizeComparison
    @State private var silhouette: UIImage?
    @State private var loaded = false

    private var tint: Color { animal.group.color }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    Text(comparison.sentence(animal: animal.name))
                        .font(FaunaFont.display(26))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("size.sentence")
                    Group {
                        if comparison.kind == .length { lengthPicture } else { weightPicture }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(comparison.sentence(animal: animal.name))
                    Text("Sizes are approximate, using the largest figure given. The silhouette is cut from the animal's photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
            }
            .navigationTitle(comparison.kind == .length ? "How long?" : "How heavy?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                silhouette = await Silhouette.make(for: animal)
                withAnimation(.smooth) { loaded = true }
            }
        }
    }

    // MARK: Length: both drawn to the same scale on a shared ground line.

    private var lengthPicture: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let animalAspect = silhouetteAspect
            let ref = comparison.reference
            let tall = comparison.dimension == .tall
            let v = CGFloat(comparison.value), rs = CGFloat(ref.size)
            // The animal's drawn width and height per metre of its measurement.
            let animalW: CGFloat = tall ? animalAspect : 1
            let animalH: CGFloat = tall ? 1 : 1 / animalAspect
            // Metres to points, so the wider of the two fills the width and neither is too tall.
            let refW = ref.upright ? rs * 0.3 : rs
            let refH = ref.upright ? rs : rs * 0.45
            let byWidth = width * 0.9 / max(v * animalW, refW)
            let byHeight = 130 / max(v * animalH, refH)
            let scale = min(byWidth, byHeight)
            return VStack(alignment: .leading, spacing: 18) {
                row(label: animal.name, size: comparison.valueText) {
                    animalShape
                        .frame(width: max(v * animalW * scale, 6), height: max(v * animalH * scale, 4))
                }
                row(label: capitalised(ref.name), size: comparison.referenceText + (ref.upright ? " tall" : "")) {
                    Image(systemName: ref.symbol)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                        .frame(width: ref.upright ? nil : max(rs * scale, 6),
                               height: ref.upright ? max(rs * scale, 6) : nil)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(height: 370)
    }

    private func row<Shape: View>(label: String, size: String, @ViewBuilder shape: () -> Shape) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            shape()
                .frame(height: 140, alignment: .bottomLeading)
            Rectangle().fill(.quaternary).frame(height: 1)
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text(store.measured(size)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Weight: the animal against a pile of the familiar thing.

    private var weightPicture: some View {
        let ref = comparison.reference
        let n = max(1, Int(comparison.ratio.rounded()))
        let shown = min(n, 12)
        return VStack(spacing: 18) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(spacing: 8) {
                    animalShape
                        .frame(width: 120, height: 120 / silhouetteAspect.clamped(0.6, 2.5))
                        .frame(height: 140, alignment: .bottom)
                    Text(store.measured(comparison.valueText)).font(.subheadline.weight(.semibold))
                }
                Text(comparison.ratio < 0.85 ? "<" : "≈")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
                VStack(spacing: 8) {
                    let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: min(shown, 4))
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(0..<(comparison.ratio < 0.85 ? 1 : shown), id: \.self) { _ in
                            Image(systemName: ref.symbol)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 140, alignment: .bottom)
                    Text(weightLabel(n: n, shown: shown))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            Text("\(capitalised(ref.name)) weighs about \(store.measured(comparison.referenceText)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func weightLabel(n: Int, shown: Int) -> String {
        let ref = comparison.reference
        if comparison.ratio < 0.85 || n == 1 { return capitalised(ref.name) }
        return n > shown ? "×\(n.formatted()) \(ref.plural)" : "\(n) \(ref.plural)"
    }

    // MARK: Shapes

    @ViewBuilder
    private var animalShape: some View {
        if let silhouette {
            Image(uiImage: silhouette)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(tint)
                .transition(.opacity)
        } else {
            Image(systemName: animal.group.symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint.opacity(loaded ? 1 : 0.3))
        }
    }

    /// Width over height of the animal's outline.
    private var silhouetteAspect: CGFloat {
        guard let s = silhouette, s.size.height > 0 else { return 1.6 }
        return (s.size.width / s.size.height).clamped(0.4, 4)
    }

    private func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
