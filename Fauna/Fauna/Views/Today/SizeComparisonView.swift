import SwiftUI

/// "How big is it?": the animal's silhouette beside something familiar.
/// Lengths: both drawn to the same scale on one ground line, each with an arrow showing what's
/// measured. Weights: bars, so a lighter animal never looks bigger.
struct SizeComparisonView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let animal: Animal
    let comparison: SizeComparison

    private var tint: Color { animal.group.color }
    private var silhouette: UIImage? { Silhouettes.image(for: animal.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(comparison.sentence(animal: animal.name))
                        .font(FaunaFont.display(26))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("size.sentence")
                    Group {
                        if comparison.kind == .length { lengthPicture } else { weightPicture }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(comparison.sentence(animal: animal.name))
                    VStack(spacing: 6) {
                        Text("Sizes are approximate, using the largest figure given.")
                        if let credit = Silhouettes.creditLine(for: animal.id) { Text(credit) }
                    }
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
        }
    }

    // MARK: Length

    /// What the animal's figure measures, in words: "long", "tall", "wingspan".
    private var animalMeasure: String {
        switch comparison.dimension {
        case .long: "long"
        case .tall: "tall"
        case .wingspan: "wingspan"
        }
    }

    private var lengthPicture: some View {
        GeometryReader { geo in
            let ref = comparison.reference
            let v = CGFloat(comparison.value), rs = CGFloat(ref.size)
            let aspect = animalAspect
            let animalVertical = comparison.dimension == .tall
            // A wingspan is wider than a bird at rest, so the bird is drawn smaller than its arrow.
            let restShare: CGFloat = comparison.dimension == .wingspan ? 0.5 : 1
            // Drawn sizes in metres, and the span each measuring arrow covers.
            let aw = animalVertical ? v * aspect : v * restShare
            let ah = animalVertical ? v : v * restShare / aspect
            let animalSpan = animalVertical ? aw : v
            let rw = ref.upright ? rs * CGFloat(ref.aspect) : rs
            let rh = ref.upright ? rs : rs / CGFloat(ref.aspect)
            let gap: CGFloat = 28
            let scale = min((geo.size.width - gap - 24) / (max(aw, animalSpan) + rw), 160 / max(ah, rh))
            return ZStack(alignment: .topLeading) {
                Rectangle().fill(.tertiary)
                    .frame(width: geo.size.width, height: 1.5)
                    .offset(y: 180)
                HStack(alignment: .top, spacing: gap) {
                    column(drawW: aw * scale, drawH: ah * scale, span: animalSpan * scale, vertical: animalVertical,
                           value: "\(store.measured(comparison.valueText)) \(animalMeasure)", name: animal.name) {
                        animalShape
                    }
                    column(drawW: rw * scale, drawH: rh * scale, span: rw * scale, vertical: ref.upright,
                           value: "\(store.measured(comparison.referenceText)) \(ref.measure)", name: capitalised(ref.name)) {
                        Image(systemName: ref.symbol)
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 260)
    }

    /// One item standing on the ground line: the drawing, a measuring arrow (beside it for a
    /// height, under it for a length), then its measurement and name.
    private func column<S: View>(drawW: CGFloat, drawH: CGFloat, span: CGFloat, vertical: Bool,
                                 value: String, name: String, @ViewBuilder shape: () -> S) -> some View {
        let width = max(drawW + (vertical ? 12 : 0), span, 96)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                shape().frame(width: max(drawW, 4), height: max(drawH, 4))
                if vertical {
                    DimensionArrow(axis: .vertical)
                        .frame(width: 8, height: max(drawH, 4))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, height: 180, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: 4) {
                if !vertical {
                    DimensionArrow(axis: .horizontal)
                        .frame(width: max(span, 8), height: 8)
                        .foregroundStyle(.secondary)
                }
                Text(value).font(.subheadline.weight(.semibold))
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.top, 8)
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: Weight

    private var weightPicture: some View {
        let ref = comparison.reference
        let heaviest = max(comparison.value, ref.size)
        return VStack(alignment: .leading, spacing: 18) {
            weightRow(name: animal.name, value: comparison.valueText, fraction: comparison.value / heaviest, color: tint) {
                animalShape
            }
            weightRow(name: capitalised(ref.name), value: comparison.referenceText, fraction: ref.size / heaviest,
                      color: Color(.systemGray)) {
                Image(systemName: ref.symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
            if comparison.ratio >= 1.5 {
                Text("That's about \(SizeComparison.count(comparison.ratio)) \(ref.plural).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weightRow<S: View>(name: String, value: String, fraction: Double, color: Color,
                                    @ViewBuilder icon: () -> S) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 56, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(store.measured(value)).font(.subheadline).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    Capsule().fill(Color(.tertiarySystemFill))
                        .overlay(alignment: .leading) {
                            Capsule().fill(color)
                                .frame(width: max(geo.size.width * CGFloat(fraction), 6))
                        }
                }
                .frame(height: 12)
            }
        }
    }

    // MARK: Shapes

    @ViewBuilder
    private var animalShape: some View {
        if let silhouette {
            Image(uiImage: silhouette)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        } else {
            Image(systemName: animal.group.symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        }
    }

    /// Width over height of the animal's silhouette.
    private var animalAspect: CGFloat {
        guard let s = silhouette, s.size.height > 0 else { return 1.6 }
        return min(max(s.size.width / s.size.height, 0.3), 8)
    }

    private func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

/// A measuring line with arrowheads at both ends.
private struct DimensionArrow: Shape {
    let axis: Axis

    func path(in r: CGRect) -> Path {
        var p = Path()
        let head: CGFloat = 4
        if axis == .horizontal {
            let y = r.midY
            p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.move(to: CGPoint(x: r.minX + head, y: y - head)); p.addLine(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.minX + head, y: y + head))
            p.move(to: CGPoint(x: r.maxX - head, y: y - head)); p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: r.maxX - head, y: y + head))
        } else {
            let x = r.midX
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.move(to: CGPoint(x: x - head, y: r.minY + head)); p.addLine(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x + head, y: r.minY + head))
            p.move(to: CGPoint(x: x - head, y: r.maxY - head)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + head, y: r.maxY - head))
        }
        return p.strokedPath(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
