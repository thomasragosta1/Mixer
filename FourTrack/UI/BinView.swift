import SwiftUI
import FourTrackCore

/// Recently Deleted. Projects stay here, playable data intact, until they're
/// recovered or permanently deleted. Permanent deletes are the only ones
/// that ask for confirmation.
struct BinView: View {
    @Bindable var model: ProjectsViewModel
    @State private var pendingDelete: [Project] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if model.binned.isEmpty {
                ContentUnavailableView("Nothing Deleted", systemImage: "trash", description: Text("Deleted projects stay here until you delete them for good."))
            } else {
                List {
                    ForEach(model.binned) { project in
                        BinRow {
                            VStack(alignment: .leading, spacing: 4) {
                                ProjectRow(project: project)
                                if let deletedAt = project.deletedAt {
                                    Text("Deleted \(deletedAt, format: .relative(presentation: .named))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } onRecover: {
                            model.recover(project)
                            if model.binned.isEmpty { dismiss() }
                        } onDelete: {
                            pendingDelete = [project]
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            pendingDelete.count == 1 ? "Delete \(pendingDelete[0].name) permanently?" : "Delete \(pendingDelete.count) projects permanently?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button(pendingDelete.count == 1 ? "Delete Permanently" : "Delete All Permanently", role: .destructive) {
                model.deletePermanently(pendingDelete)
                pendingDelete = []
                if model.binned.isEmpty { dismiss() }
            }
        } message: {
            Text("All tracks will be erased. This can't be undone.")
        }
    }
}
