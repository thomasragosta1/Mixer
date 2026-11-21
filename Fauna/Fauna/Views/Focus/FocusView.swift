import SwiftUI

/// Settings-style rows for choosing kinds of animals and places. Empty selections mean "everything".
/// Put inside a `List` or `Form`.
struct FocusSections: View {
    @Binding var groups: Set<AnimalGroup>
    @Binding var regions: Set<Region>

    var body: some View {
        Section {
            ForEach(AnimalGroup.allCases) { group in
                CheckRow(title: group.title, symbol: group.symbol, tint: group.color,
                         isOn: groups.contains(group)) { toggle(group, in: &groups) }
            }
        } header: {
            Text("Kinds of Animals")
        } footer: {
            Text(groups.isEmpty ? "Choose none for every kind of animal." : "")
        }

        Section {
            ForEach(Region.allCases) { region in
                CheckRow(title: region.title, symbol: region.symbol, tint: regionTint(region),
                         isOn: regions.contains(region)) { toggle(region, in: &regions) }
            }
        } header: {
            Text("Places")
        } footer: {
            Text(regions.isEmpty ? "Choose none for animals from everywhere." : "")
        }
    }

    private func regionTint(_ region: Region) -> Color {
        switch region {
        case .arctic, .antarctica: .cyan
        case .openOcean: .blue
        case .africa, .southAmerica, .centralAmerica: .orange
        case .asia, .oceania: .red
        case .europe: .indigo
        case .naEast, .naWest: .green
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        Haptics.select()
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

/// A Settings-style row: colored icon tile, title, and a checkmark when selected.
struct CheckRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, tint: tint)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The rounded-square symbol tile used in iOS Settings.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FocusView: View {
    @Environment(AppStore.self) private var store
    @State private var groups: Set<AnimalGroup> = []
    @State private var regions: Set<Region> = []
    @State private var reminderTime = Date()
    @State private var notificationsDenied = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                } footer: {
                    Text("Want bugs in eastern Canada? Choose Insects & Bugs and Eastern North America.")
                }

                FocusSections(groups: $groups, regions: $regions)

                Section {
                    Toggle(isOn: Binding(get: { store.state.reminderEnabled }, set: setReminder)) {
                        HStack(spacing: 12) {
                            IconTile(symbol: "bell.badge.fill", tint: .red)
                            Text("Daily Animal")
                        }
                    }
                    if store.state.reminderEnabled {
                        DatePicker(selection: $reminderTime, displayedComponents: .hourAndMinute) {
                            HStack(spacing: 12) {
                                IconTile(symbol: "clock.fill", tint: .blue)
                                Text("Time")
                            }
                        }
                    }
                    if notificationsDenied {
                        Button("Turn On Notifications in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("A notification each day naming the animal that's waiting for you.")
                }

                Section {
                    Link(destination: URL(string: "https://en.wikipedia.org/wiki/Wikipedia:Text_of_the_Creative_Commons_Attribution-ShareAlike_4.0_International_License")!) {
                        HStack(spacing: 12) {
                            IconTile(symbol: "book.closed.fill", tint: .gray)
                            Text("Sources & Licenses")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button("Reset Journal", role: .destructive) { confirmReset = true }
                } header: {
                    Text("About")
                } footer: {
                    Text("Articles are condensed from Wikipedia (CC BY-SA 4.0). Photos come from Wikimedia Commons. Donation links open each organization's own website; Fauna never handles money.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Focus")
            .onAppear(perform: load)
            .onChange(of: groups) { _, _ in saveFocus() }
            .onChange(of: regions) { _, _ in saveFocus() }
            .onChange(of: reminderTime) { _, time in
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                guard c.hour != store.state.reminderHour || c.minute != store.state.reminderMinute else { return }
                store.state.reminderHour = c.hour ?? 8
                store.state.reminderMinute = c.minute ?? 0
                Task { await Reminders.reschedule(store) }
            }
            .confirmationDialog("Start your journal over?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Journal", role: .destructive) {
                    store.resetProgress()
                    Task { await Reminders.reschedule(store) }
                }
            } message: {
                Text("Every animal you've met will be forgotten, and today's animal will change.")
            }
        }
    }

    private var summary: some View {
        let pool = store.library.filter { store.matchesFocus($0, groups: groups, regions: regions) }
        let unmet = pool.filter { !store.metIDs.contains($0.id) }.count
        return HStack(spacing: 12) {
            IconTile(symbol: pool.isEmpty ? "exclamationmark.triangle.fill" : "scope",
                     tint: pool.isEmpty ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(pool.isEmpty ? "No Matches Yet" : "\(pool.count) Animals Match")
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(pool.isEmpty ? "Fauna will pick from everywhere." : "\(unmet) you haven't met yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .animation(.smooth, value: pool.count)
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
