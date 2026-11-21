import SwiftUI
import MapKit

/// An animal's Wikipedia lead photo, filling its frame. Shows tinted art while loading or offline.
struct AnimalPhoto: View {
    let animal: Animal
    var size: WikiImages.Size = .card
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: animal.group.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.45)))
                } else {
                    Image(systemName: animal.group.symbol)
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            .clipped()
            .task(id: animal.id + "\(size.rawValue)") {
                image = nil
                let loaded = await WikiImages.shared.image(for: animal.wikipediaTitle, size: size)
                withAnimation(.easeOut(duration: 0.45)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// A selectable capsule with an SF Symbol, used for focus filters.
struct SelectChip: View {
    let title: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : symbol)
                    .font(.footnote.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isOn ? .white : .primary)
            .background {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Material.thinMaterial))
                Capsule()
                    .strokeBorder(isOn ? .clear : Color.primary.opacity(0.08))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOn)
    }
}

/// Compact IUCN label like "EN · Endangered".
struct StatusPill: View {
    let status: ConservationStatus
    var onDark = false

    var body: some View {
        if onDark {
            label
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
        } else {
            label
                .foregroundStyle(.primary)
                .background(status.color.opacity(0.14), in: Capsule())
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(status.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Conservation status: \(status.title)")
    }
}

struct GroupPill: View {
    let group: AnimalGroup
    var body: some View {
        Label(group.singular, systemImage: group.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

/// The seven-step Red List scale with the animal's category raised and labeled.
struct ConservationScale: View {
    let status: ConservationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(ConservationStatus.scale, id: \.self) { step in
                    let current = step == status
                    VStack(spacing: 6) {
                        Text(step.rawValue)
                            .font(.system(size: current ? 13 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(current ? .white : step.color)
                            .frame(maxWidth: .infinity)
                            .frame(height: current ? 34 : 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(current ? AnyShapeStyle(step.color) : AnyShapeStyle(step.color.opacity(0.15)))
                            )
                            .shadow(color: current ? step.color.opacity(0.45) : .clear, radius: 8, y: 4)
                    }
                    .frame(height: 34, alignment: .bottom)
                }
            }
            HStack {
                Text("Least concern")
                Spacer()
                Text("Extinct")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if status.scaleIndex == nil {
                Text("\(status.title): the IUCN has not placed this species on the scale.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("IUCN Red List: \(status.title)")
    }
}

/// A small satellite map centered on the animal's home range. Not interactive.
struct RangeMap: View {
    let animal: Animal

    var body: some View {
        let center = CLLocationCoordinate2D(latitude: animal.coordinate.latitude, longitude: animal.coordinate.longitude)
        let span = MKCoordinateSpan(latitudeDelta: min(animal.mapSpan, 150), longitudeDelta: min(animal.mapSpan * 1.6, 300))
        Map(initialPosition: .region(MKCoordinateRegion(center: center, span: span)), interactionModes: []) {
            Annotation(animal.name, coordinate: center, anchor: .center) {
                ZStack {
                    Circle().fill(animal.group.color.opacity(0.25)).frame(width: 54, height: 54)
                    Circle().fill(animal.group.color).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    Image(systemName: animal.group.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.imagery(elevation: .realistic))
        .allowsHitTesting(false)
        .accessibilityLabel("Map of the \(animal.name)'s range: \(animal.range)")
    }
}
