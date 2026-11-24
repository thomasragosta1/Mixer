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
                        // A photo scaled to fill spills past its frame; it must never take taps,
                        // or a wide photo steals them from the card beside it.
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(.easeOut(duration: 0.45)))
                } else {
                    Image(systemName: animal.group.symbol)
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            .clipped()
            // clipped() only trims the drawing: a wide photo scaled to fill still takes taps
            // beyond the frame, stealing them from neighbouring cards. Limit taps to the frame.
            .contentShape(Rectangle())
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

/// A satellite picture of the animal's home range with a marker in the middle.
///
/// A live 3D map loads slowly (especially zoomed out to a whole ocean), so this renders a flat
/// snapshot once and caches it on disk; after that it appears instantly.
struct RangeMap: View {
    let animal: Animal
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(red: 0.12, green: 0.16, blue: 0.2))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity)
                } else if unavailable {
                    // Offline and never rendered before: say so instead of spinning forever.
                    Label("Map appears when you're online", systemImage: "wifi.slash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 14)
                } else {
                    ProgressView().tint(.white)
                }
                marker
                // Apple requires its maps to be credited.
                Text("\u{F8FF}Maps")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityLabel("Apple Maps")
            }
            .task(id: animal.id) {
                let size = CGSize(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
                let loaded = await RangeSnapshots.shared.image(for: animal, size: size)
                withAnimation(.easeOut(duration: 0.3)) { image = loaded }
                unavailable = loaded == nil
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of the \(animal.name)'s range: \(animal.range)")
    }

    private var marker: some View {
        ZStack {
            Circle().fill(animal.group.color.opacity(0.3)).frame(width: 54, height: 54)
            Circle().fill(animal.group.color).frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Image(systemName: animal.group.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

/// Renders and caches range map snapshots.
actor RangeSnapshots {
    static let shared = RangeSnapshots()
    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let d = caches.appendingPathComponent("RangeMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Renders maps ahead of time so they're there offline.
    func prefetch(_ animals: [Animal], size: CGSize) async {
        for animal in animals {
            if Task.isCancelled { return }
            _ = await image(for: animal, size: size)
        }
    }

    func image(for animal: Animal, size: CGSize) async -> UIImage? {
        let key = "\(animal.id)-\(Int(size.width))x\(Int(size.height))-v1"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = dir?.appendingPathComponent(key + ".jpg")
        if let file, let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }
        let options = MKMapSnapshotter.Options()
        let lat = animal.coordinate.latitude
        // Keep the region inside the valid latitude range so wide ocean views still render.
        let latSpan = max(1, min(animal.mapSpan, 170 - 2 * abs(lat)))
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: animal.coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: min(latSpan * 1.6, 359)))
        options.size = size
        options.mapType = .satellite
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let img = snapshot.image
        memory.setObject(img, forKey: key as NSString)
        if let file, let data = img.jpegData(compressionQuality: 0.8) { try? data.write(to: file) }
        return img
    }
}

/// "Photo: Jane Smith, CC BY-SA 4.0", loaded from Wikimedia Commons; taps open the file's page.
struct PhotoCreditLine: View {
    let animal: Animal
    var onDark = false
    @Environment(\.openURL) private var openURL
    @State private var credit: PhotoCredit?

    var body: some View {
        // Always render something: SwiftUI doesn't run .task on a view with no content,
        // so an empty placeholder would never load the credit.
        Button {
            if let credit { openURL(credit.pageURL) }
        } label: {
            Text(credit?.line ?? "Photo: Wikimedia Commons")
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(onDark ? Color.white.opacity(0.85) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(credit == nil)
        .accessibilityHint("Opens the photo's page on Wikimedia Commons")
        .task(id: animal.id) {
            credit = await WikiImages.shared.credit(for: animal.wikipediaTitle)
        }
    }
}
