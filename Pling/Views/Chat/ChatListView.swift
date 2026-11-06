import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var showNewChat = false

    private var filtered: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter { store.title(for: $0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Chats") {
                Button {
                    showNewChat = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel("Neuer Chat")
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Suchen", text: $search)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 6)

            if store.conversations.isEmpty {
                EmptyChatsView { showNewChat = true }
            } else {
                List {
                    ForEach(filtered) { conversation in
                        Button {
                            store.activeChat = ChatRoute(id: conversation.id)
                        } label: {
                            ChatRow(conversation: conversation)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    Color.clear.frame(height: 70).listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showNewChat) {
            NewChatView()
                .environmentObject(store)
        }
    }
}

struct ChatRow: View {
    @EnvironmentObject private var store: AppStore
    let conversation: Conversation

    var body: some View {
        let status = store.status(for: conversation)
        HStack(spacing: 12) {
            AvatarView(user: store.avatarUser(for: conversation), size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.title(for: conversation))
                    .font(.body.weight(status.isUnread ? .bold : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: status.symbol)
                        .font(.caption)
                        .foregroundStyle(status.color)
                    Text(subtitle(status))
                        .font(.subheadline.weight(status.isUnread ? .bold : .regular))
                        .foregroundStyle(status.isUnread ? status.color : .secondary)
                        .lineLimit(1)
                    if status != .empty {
                        Text("· \(conversation.lastActivity.shortAgo)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)
            StreakBadge(count: conversation.activeStreak)
            Image(systemName: "camera")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ status: ChatStatus) -> String {
        // Bei neuen Textnachrichten den Anfang der Nachricht zeigen
        if status == .newMessage || status == .receivedMessage, let text = conversation.lastMessageText {
            if conversation.isGroup, let sender = conversation.lastSenderID, let name = store.user(sender)?.displayName {
                return "\(name): \(text)"
            }
            return text
        }
        return status.label
    }
}

struct EmptyChatsView: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("💬").font(.system(size: 64))
            Text("Noch keine Chats")
                .font(.title3.bold())
            Text("Füge Freunde hinzu und schick ihnen deinen ersten Snap!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Neuer Chat", action: onNewChat)
                .buttonStyle(.borderedProminent)
            Spacer()
            Spacer()
        }
        .padding()
    }
}
