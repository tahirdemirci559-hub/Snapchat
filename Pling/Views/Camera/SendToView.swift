import SwiftUI

/// „Senden an…“: Story, Gruppen und Freunde auswählen.
struct SendToView: View {
    @EnvironmentObject private var store: AppStore
    let image: UIImage
    let duration: Int?
    let onDone: (Bool) -> Void

    @State private var toStory = false
    @State private var selectedFriends: Set<String> = []
    @State private var selectedGroups: Set<String> = []
    @State private var search = ""
    @State private var isSending = false

    private var groups: [Conversation] { store.conversations.filter(\.isGroup) }

    private var filteredFriends: [UserProfile] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.friends }
        return store.friends.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) || $0.username.localizedCaseInsensitiveContains(q)
        }
    }

    private var hasSelection: Bool { toStory || !selectedFriends.isEmpty || !selectedGroups.isEmpty }

    private var selectionSummary: String {
        var names: [String] = []
        if toStory { names.append("Meine Story") }
        names += groups.filter { selectedGroups.contains($0.id) }.map { store.title(for: $0) }
        names += store.friends.filter { selectedFriends.contains($0.id) }.map(\.displayName)
        return names.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    selectableRow(isOn: toStory) {
                        toStory.toggle()
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 2))
                        VStack(alignment: .leading) {
                            Text("Meine Story").font(.body.bold())
                            Text("Alle Freunde · 24 Stunden").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !groups.isEmpty {
                    Section("Gruppen") {
                        ForEach(groups) { group in
                            selectableRow(isOn: selectedGroups.contains(group.id)) {
                                toggle(group.id, in: &selectedGroups)
                            } label: {
                                AvatarView(user: store.avatarUser(for: group), size: 44)
                                Text(store.title(for: group)).font(.body.weight(.semibold))
                            }
                        }
                    }
                }

                Section("Freunde") {
                    if store.friends.isEmpty {
                        Text("Noch keine Freunde – füge welche über das ➕-Symbol hinzu.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredFriends) { friend in
                        selectableRow(isOn: selectedFriends.contains(friend.id)) {
                            toggle(friend.id, in: &selectedFriends)
                        } label: {
                            AvatarView(user: friend, size: 44)
                            VStack(alignment: .leading) {
                                Text(friend.displayName).font(.body.weight(.semibold))
                                Text("@\(friend.username)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Freunde suchen")
            .navigationTitle("Senden an …")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zurück") { onDone(false) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasSelection {
                    HStack {
                        Text(selectionSummary)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer()
                        Button(action: send) {
                            HStack {
                                if isSending { ProgressView().tint(.white) }
                                Image(systemName: "paperplane.fill")
                            }
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Theme.gradient, in: Circle())
                        }
                        .disabled(isSending)
                        .accessibilityLabel("Jetzt senden")
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private func selectableRow<Content: View>(isOn: Bool,
                                            action: @escaping () -> Void,
                                            @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label()
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? Theme.brand : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func send() {
        isSending = true
        Task {
            let ok = await store.sendSnap(image, duration: duration,
                                          toFriends: Array(selectedFriends),
                                          toConversations: Array(selectedGroups),
                                          toStory: toStory)
            isSending = false
            if ok { onDone(true) }
        }
    }
}
