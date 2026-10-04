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
                    Section {
                        ForEach(model.binned) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                ProjectRow(project: project)
                                if let deletedAt = project.deletedAt {
                                    Text("Deleted \(deletedAt, format: .relative(presentation: .named))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    model.recover(project)
                                } label: {
                                    Label("Recover", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = [project]
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    model.recover(project)
                                } label: {
                                    Label("Recover", systemImage: "arrow.uturn.backward")
                                }
                                Button(role: .destructive) {
                                    pendingDelete = [project]
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAction(named: "Recover") { model.recover(project) }
                            .accessibilityAction(named: "Delete permanently") { pendingDelete = [project] }
                        }
                    } footer: {
                        Text("Swipe right to recover, or left to delete permanently.")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.binned.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            model.binned.forEach { model.recover($0) }
                        } label: {
                            Label("Recover All", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            pendingDelete = model.binned
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
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
