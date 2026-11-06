import SwiftUI

/// Neuen Chat starten – mit einer Person oder als Gruppe.
struct NewChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []
    @State private var groupName = ""
    @State private var isLoading = false

    private var isGroup: Bool { selected.count > 1 }

    var body: some View {
        NavigationStack {
            List {
                if isGroup {
                    Section("Gruppenname") {
                        TextField("z. B. Familie 🏡", text: $groupName)
                    }
                }

                Section("Freunde auswählen") {
                    if store.friends.isEmpty {
                        Button("Zuerst Freunde hinzufügen") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showAddFriend = true }
                        }
                    }
                    ForEach(store.friends) { friend in
                        Button {
                            if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(user: friend, size: 40)
                                VStack(alignment: .leading) {
                                    Text(friend.displayName).font(.body.weight(.semibold))
                                    Text("@\(friend.username)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(friend.id) ? Theme.brand : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Neuer Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isGroup ? "Gruppe erstellen" : "Chat") { start() }
                        .disabled(selected.isEmpty || isLoading || (isGroup && groupName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
        }
    }

    private func start() {
        isLoading = true
        let ids = Array(selected)
        let title = isGroup ? groupName.trimmingCharacters(in: .whitespaces) : nil
        Task {
            dismiss()
            try? await Task.sleep(nanoseconds: 350_000_000)
            await store.openChat(with: ids, title: title)
        }
    }
}
