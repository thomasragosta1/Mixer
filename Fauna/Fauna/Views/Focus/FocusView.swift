import SwiftUI

/// Chips for choosing kinds of animals and places. Empty selections mean "everything".
struct FocusPicker: View {
    @Binding var groups: Set<AnimalGroup>
    @Binding var regions: Set<Region>
    var onDark = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Kinds of animals", color: onDark ? .white.opacity(0.7) : .secondary)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(AnimalGroup.allCases) { group in
                        SelectChip(title: group.title, symbol: group.symbol, tint: group.color,
                                   isOn: groups.contains(group)) { toggle(group, in: &groups) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Places", color: onDark ? .white.opacity(0.7) : .secondary)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Region.allCases) { region in
                        SelectChip(title: region.title, symbol: region.symbol, tint: .faunaMoss,
                                   isOn: regions.contains(region)) { toggle(region, in: &regions) }
                    }
                }
            }
        }
        .environment(\.colorScheme, onDark ? .dark : colorScheme)
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

struct FocusView: View {
    @Environment(AppStore.self) private var store
    @State private var groups: Set<AnimalGroup> = []
    @State private var regions: Set<Region> = []
    @State private var reminderTime = Date()
    @State private var notificationsDenied = false
    @State private var confirmReset = false
    @State private var offlineReady: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    card {
                        FocusPicker(groups: $groups, regions: $regions)
                            matchSummary
                    }
                    card { reminderSection }
                    card { unitsSection }
                    card { aboutSection }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Focus")
            .onAppear(perform: load)
            .task { offlineReady = OfflineLibrary.readyCount(store) }
            .onChange(of: groups) { _, _ in saveFocus() }
            .onChange(of: regions) { _, _ in saveFocus() }
            .confirmationDialog("Start your journal over?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset journal", role: .destructive) {
                    store.resetProgress()
                    Task { await Reminders.reschedule(store) }
                }
            } message: {
                Text("Every animal you've met will be forgotten, and today's animal will change.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Narrow your daily animal to the creatures and places you care about. Want bugs in eastern Canada? Pick Insects & Bugs and Eastern North America.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var matchSummary: some View {
        let pool = store.library.filter { store.matchesFocus($0, groups: groups, regions: regions) }
        let unmet = pool.filter { !store.metIDs.contains($0.id) }.count
        return HStack(spacing: 10) {
            Image(systemName: pool.isEmpty ? "exclamationmark.triangle.fill" : "scope")
                .foregroundStyle(pool.isEmpty ? .orange : Color.faunaMoss)
            VStack(alignment: .leading, spacing: 2) {
                Text(pool.isEmpty ? "No animals match yet" : "\(pool.count) animals match")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Text(pool.isEmpty ? "We'll pick from everywhere until more are added." :
                        "\(unmet) you haven't met. When they run out, Fauna picks from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth, value: pool.count)
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { store.state.reminderEnabled }, set: setReminder)) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily animal").font(.headline)
                        Text("A notification with the name of each new animal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.red)
                }
            }
            .tint(.faunaMoss)
            if store.state.reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderTime) { _, time in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        store.state.reminderHour = c.hour ?? 8
                        store.state.reminderMinute = c.minute ?? 0
                        Task { await Reminders.reschedule(store) }
                    }
            }
            if notificationsDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Notifications are off for Fauna. Turn them on in Settings.", systemImage: "gear")
                        .font(.footnote)
                }
            }
        }
        .animation(.smooth, value: store.state.reminderEnabled)
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Units").font(.headline)
                    Text(unitsCaption)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "ruler.fill").foregroundStyle(.blue)
            }
            Picker("Units", selection: Binding(get: { store.state.units }, set: { store.state.units = $0 })) {
                ForEach(UnitPreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var unitsCaption: String {
        switch store.state.units {
        case .automatic: "Following your iPhone's setting: \(store.usesImperial ? "feet, pounds, miles" : "metres, kilograms, kilometres")."
        case .metric: "Metres, kilograms, kilometres."
        case .imperial: "Feet, pounds, miles."
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About Fauna").font(.headline)
                    Text("Articles are adapted from Wikipedia under CC BY-SA 4.0. Photos come from Wikimedia Commons, each under its own license. Donation links go straight to each organization's own website; Fauna never handles money.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "leaf.fill").foregroundStyle(Color.faunaMoss)
            }
            if let offlineReady {
                Label("\(offlineReady) new animals ready to read offline, photos included.",
                      systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                SourcesView()
            } label: {
                Label("Sources & Licenses", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
            }
            Divider()
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset journal", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Actions

    private func load() {
        groups = store.focusGroups
        regions = store.focusRegions
        reminderTime = Calendar.current.date(bySettingHour: store.state.reminderHour,
                                             minute: store.state.reminderMinute, second: 0, of: .now) ?? .now
        Task {
            let status = await Reminders.authorizationStatus()
            notificationsDenied = store.state.reminderEnabled && status == .denied
        }
    }

    private func saveFocus() {
        guard groups != store.focusGroups || regions != store.focusRegions else { return }
        store.setFocus(groups: groups, regions: regions)
        Task { await Reminders.reschedule(store) }
    }

    private func setReminder(_ on: Bool) {
        store.state.reminderEnabled = on
        Task {
            if on {
                let granted = await Reminders.requestAuthorization()
                notificationsDenied = !granted
            } else {
                notificationsDenied = false
            }
            await Reminders.reschedule(store)
        }
    }
}
