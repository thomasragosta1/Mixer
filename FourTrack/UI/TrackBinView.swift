import SwiftUI
import FourTrackCore

/// One row in a Recently Deleted list: what it is, and two buttons.
struct BinRow<Info: View>: View {
    @ViewBuilder let info: () -> Info
    let onRecover: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            info()
            HStack(spacing: 10) {
                Button(action: onRecover) {
                    Label("Recover", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .tint(.red)
            }
            .controlSize(.regular)
        }
        .padding(.vertical, 6)
    }
}

/// A project's own Recently Deleted (3 dots → Recently Deleted). Tracks dragged
/// to the bin wait here with their audio until recovered or deleted for good.
struct TrackBinView: View {
    @Bindable var model: ProjectViewModel
    @State private var pendingDelete: DeletedTrack?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.project.deletedTracks.isEmpty {
                    ContentUnavailableView(
                        "No Deleted Tracks",
                        systemImage: "trash",
                        description: Text("Swipe left from the right edge of a track to delete it. It waits here until you recover it or delete it for good.")
                    )
                } else {
                    List {
                        ForEach(model.project.deletedTracks.reversed()) { entry in
                            BinRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Image(systemName: entry.track.isDrums ? "square.grid.3x2" : "waveform")
                                            .foregroundStyle(.secondary)
                                        Text(entry.track.name).font(.headline)
                                        Spacer()
                                        Text(TimeFormat.duration(entry.track.durationSeconds))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Deleted \(entry.deletedAt, format: .relative(presentation: .named))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            } onRecover: {
                                model.recoverTrack(entry.id)
                            } onDelete: {
                                pendingDelete = entry
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete \(pendingDelete?.track.name ?? "this track") permanently?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = pendingDelete { model.deleteTrackPermanently(entry.id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Its audio will be erased. This can't be undone.")
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
