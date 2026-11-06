import SwiftUI

struct AddFriendView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("Benutzername", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(add)
                        if isLoading {
                            ProgressView()
                        } else {
                            Button("Hinzufügen", action: add)
                                .disabled(username.trimmingCharacters(in: .whitespaces).count < 3)
                        }
                    }
                    if let message {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isError ? .red : .green)
                    }
                } header: {
                    Text("Freund hinzufügen")
                } footer: {
                    if store.backend.isDemo {
                        Text("Demo-Modus: Probier mal „opa“ 👴")
                    } else {
                        Text("Frag deine Familie und Freunde nach ihrem Pling-Benutzernamen.")
                    }
                }

                if let me = store.me {
                    Section("Dein Benutzername") {
                        HStack {
                            Text("@\(me.username)").font(.body.bold())
                            Spacer()
                            ShareLink(item: "Füg mich bei Pling hinzu! Mein Benutzername: @\(me.username) ⚡️") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }

                Section("Meine Freunde (\(store.friends.count))") {
                    if store.friends.isEmpty {
                        Text("Noch keine Freunde").foregroundStyle(.secondary)
                    }
                    ForEach(store.friends) { friend in
                        HStack(spacing: 12) {
                            AvatarView(user: friend, size: 40)
                            VStack(alignment: .leading) {
                                Text(friend.displayName).font(.body.weight(.semibold))
                                Text("@\(friend.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                dismiss()
                                Task {
                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                    await store.openChat(with: [friend.id])
                                }
                            } label: {
                                Image(systemName: "bubble.left.fill")
                                    .foregroundStyle(Theme.chat)
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await store.removeFriend(friend) }
                            } label: {
                                Label("Entfernen", systemImage: "person.fill.xmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Freunde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func add() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3, !isLoading else { return }
        isLoading = true
        message = nil
        Task {
            do {
                let friend = try await store.addFriend(username: name)
                message = "\(friend.emoji) \(friend.displayName) ist jetzt dein Freund!"
                isError = false
                username = ""
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isError = true
            }
            isLoading = false
        }
    }
}
