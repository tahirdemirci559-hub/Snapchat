import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var emoji = ""
    @State private var colorHex = ""
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        AvatarView(user: preview, size: 110)
                        Text(displayName.isEmpty ? "Ohne Namen" : displayName)
                            .font(.title2.bold())
                        if let me = store.me {
                            Text("@\(me.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ShareLink(item: inviteText(for: me)) {
                                Label("Profil teilen", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Profil bearbeiten") {
                    TextField("Name", text: $displayName)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Theme.avatarEmojis, id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 26))
                                    .frame(width: 42, height: 42)
                                    .background(emoji == item ? Color(hex: colorHex).opacity(0.3) : Color.clear, in: Circle())
                                    .onTapGesture { emoji = item }
                            }
                        }
                    }
                    ColorRow(selection: $colorHex)
                    Button("Speichern") {
                        Task {
                            await store.updateProfile(displayName: displayName.trimmingCharacters(in: .whitespaces),
                                                      emoji: emoji, colorHex: colorHex)
                            dismiss()
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || !hasChanges)
                }

                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showAddFriend = true }
                    } label: {
                        Label("Freunde (\(store.friends.count))", systemImage: "person.2.fill")
                    }
                }

                Section("Info") {
                    LabeledContent("Modus", value: store.backend.modeDescription)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    if store.backend.isDemo {
                        Text("Im Demo-Modus sind Mama, Papa, Lena und Opa Test-Freunde. Für echte Chats mit deiner Familie richte Firebase ein (siehe README).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Abmelden", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Wirklich abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { store.signOut() }
            } message: {
                Text(store.backend.isDemo
                     ? "Im Demo-Modus wird danach ein neues Konto angelegt."
                     : "Ohne E-Mail-Login kann das Konto nach dem Abmelden nicht wiederhergestellt werden.")
            }
            .onAppear(perform: loadValues)
        }
    }

    private var preview: UserProfile? {
        guard var me = store.me else { return nil }
        me.displayName = displayName
        me.emoji = emoji
        me.colorHex = colorHex
        return me
    }

    private var hasChanges: Bool {
        guard let me = store.me else { return false }
        return me.displayName != displayName || me.emoji != emoji || me.colorHex != colorHex
    }

    private func loadValues() {
        guard let me = store.me else { return }
        displayName = me.displayName
        emoji = me.emoji
        colorHex = me.colorHex
    }

    private func inviteText(for me: UserProfile) -> String {
        "Füg mich bei Pling hinzu! Mein Benutzername: @\(me.username) ⚡️"
    }
}
