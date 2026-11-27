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

    /// The animal above the familiar object, both starting from the same edge at the same scale,
    /// each with a measuring arrow and its measurement on the right.
    private var lengthPicture: some View {
        GeometryReader { geo in
            let ref = comparison.reference
            let v = CGFloat(comparison.value), rs = CGFloat(ref.size)
            let aspect = animalAspect
            // The fact decides the axis for both: heights are measured upright, lengths end to end
            // (bill to tail, nose to tail), whatever pose the silhouette is in.
            let animalVertical = comparison.dimension == .tall
            // A wingspan is wider than a bird at rest, so the bird is drawn smaller than its arrow.
            let restShare: CGFloat = comparison.dimension == .wingspan ? 0.5 : 1
            // Drawn sizes in metres, and the span each measuring arrow covers.
            let aw = animalVertical ? v * aspect : v * restShare
            let ah = animalVertical ? v : v * restShare / aspect
            let animalSpan = animalVertical ? aw : v
            let rw = ref.upright ? rs * CGFloat(ref.aspect) : rs
            let rh = ref.upright ? rs : rs / CGFloat(ref.aspect)
            // Heights compare side by side on one ground line; lengths stacked from one edge.
            if animalVertical {
                let gap: CGFloat = 32
                let sideScale = min((geo.size.width - gap - 70) / (max(aw, animalSpan) + rw), 170 / max(ah, rh))
                return AnyView(HStack(alignment: .top, spacing: gap) {
                    standing(drawW: aw * sideScale, drawH: ah * sideScale, span: animalSpan * sideScale,
                             vertical: animalVertical, guides: comparison.dimension != .wingspan,
                             value: "\(store.measured(comparison.valueText)) \(animalMeasure)", name: animal.name) {
                        animalShape
                    }
                    standing(drawW: rw * sideScale, drawH: rh * sideScale, span: rw * sideScale,
                             vertical: ref.upright, guides: true,
                             value: "\(store.measured(comparison.referenceText)) \(ref.measure)", name: capitalised(ref.name)) {
                        Image(systemName: ref.symbol).resizable().foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .background(alignment: .topLeading) {
                    Rectangle().fill(.tertiary).frame(height: 1.5).offset(y: 180)
                })
            }
            let labelWidth: CGFloat = 112
            let drawWidth = geo.size.width - labelWidth - 12
            let scale = min(drawWidth / max(aw, animalSpan, rw), 120 / max(ah, rh))
            let shorter = min(max(aw, animalSpan), rw) * scale
            // Only meaningful when both are measured end to end.
            let showDash = !animalVertical && !ref.upright
            return AnyView(VStack(alignment: .leading, spacing: 22) {
                row(drawW: aw * scale, drawH: ah * scale, span: animalSpan * scale, vertical: animalVertical,
                    guides: comparison.dimension != .wingspan, drawWidth: drawWidth, labelWidth: labelWidth,
                    value: "\(store.measured(comparison.valueText)) \(animalMeasure)", name: animal.name) {
                    animalShape
                }
                row(drawW: rw * scale, drawH: rh * scale, span: rw * scale, vertical: ref.upright,
                    guides: true, drawWidth: drawWidth, labelWidth: labelWidth,
                    value: "\(store.measured(comparison.referenceText)) \(ref.measure)", name: capitalised(ref.name)) {
                    Image(systemName: ref.symbol)
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .background(alignment: .topLeading) {
                // Both start on this line; the dashed one shows where the shorter one ends.
                Rectangle().fill(.tertiary).frame(width: 1.5)
                if showDash {
                    Line()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 1)
                        .offset(x: shorter)
                }
            })
        }
        .frame(height: 300)
    }

    /// An item standing on the shared ground line (side-by-side layout): the drawing with its
    /// measuring arrow, then the measurement and name underneath.
    private func standing<S: View>(drawW: CGFloat, drawH: CGFloat, span: CGFloat, vertical: Bool, guides: Bool,
                                   value: String, name: String, @ViewBuilder shape: () -> S) -> some View {
        let w = max(drawW, 4), h = max(drawH, 4)
        let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                shape().frame(width: w, height: h)
                if vertical {
                    ZStack(alignment: .leading) {
                        if guides {
                            VStack(spacing: 0) {
                                Line(horizontal: true).stroke(style: dash).frame(height: 1)
                                Spacer(minLength: 0)
                                Line(horizontal: true).stroke(style: dash).frame(height: 1)
                            }
                            .frame(width: 14, height: h)
                        }
                        DimensionArrow(axis: .vertical).frame(width: 8, height: h).offset(x: 10)
                    }
                    .frame(width: 22, height: h, alignment: .leading)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: 4) {
                if !vertical {
                    ZStack(alignment: .topLeading) {
                        if guides {
                            HStack(spacing: 0) {
                                Line().stroke(style: dash).frame(width: 1)
                                Spacer(minLength: 0)
                                Line().stroke(style: dash).frame(width: 1)
                            }
                            .frame(width: max(span, 8), height: 10)
                        }
                        DimensionArrow(axis: .horizontal).frame(width: max(span, 8), height: 8).offset(y: 6)
                    }
                    .frame(height: 16, alignment: .topLeading)
                    .foregroundStyle(.secondary)
                }
                Text(value).font(.subheadline.weight(.semibold))
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.top, 6)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    /// One item with its measurement drawn on it: the shape spans exactly the measured length,
    /// with dashed guides from its two ends to the measuring arrow (beside it for heights).
    private func row<S: View>(drawW: CGFloat, drawH: CGFloat, span: CGFloat, vertical: Bool, guides: Bool,
                              drawWidth: CGFloat, labelWidth: CGFloat,
                              value: String, name: String, @ViewBuilder shape: () -> S) -> some View {
        let w = max(drawW, 4), h = max(drawH, 4)
        let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
        return HStack(alignment: .bottom, spacing: 12) {
            Group {
                if vertical {
                    HStack(alignment: .bottom, spacing: 0) {
                        shape().frame(width: w, height: h)
                        ZStack(alignment: .leading) {
                            if guides {
                                // Guides from the top and bottom of the shape across to the arrow.
                                VStack(spacing: 0) {
                                    Line(horizontal: true).stroke(style: dash).frame(height: 1)
                                    Spacer(minLength: 0)
                                    Line(horizontal: true).stroke(style: dash).frame(height: 1)
                                }
                                .frame(width: 14, height: h)
                            }
                            DimensionArrow(axis: .vertical)
                                .frame(width: 8, height: h)
                                .offset(x: 10)
                        }
                        .frame(width: 22, height: h, alignment: .leading)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        shape().frame(width: w, height: h)
                        ZStack(alignment: .topLeading) {
                            if guides {
                                // Guides down from the shape's two ends to the arrow.
                                HStack(spacing: 0) {
                                    Line().stroke(style: dash).frame(width: 1)
                                    Spacer(minLength: 0)
                                    Line().stroke(style: dash).frame(width: 1)
                                }
                                .frame(width: max(span, 8), height: 14)
                            }
                            DimensionArrow(axis: .horizontal)
                                .frame(width: max(span, 8), height: 8)
                                .offset(y: 10)
                        }
                        .frame(height: 20, alignment: .topLeading)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: drawWidth, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.weight(.semibold))
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(width: labelWidth, alignment: .leading)
        }
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

/// A line through the middle of its frame: vertical by default, or horizontal.
private struct Line: Shape {
    var horizontal = false

    func path(in r: CGRect) -> Path {
        var p = Path()
        if horizontal {
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        } else {
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        }
        return p
    }
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
