import SwiftUI

enum MainTab: Int, CaseIterable {
    case chats, camera, stories
}

struct ChatRoute: Identifiable, Hashable {
    let id: String
}

enum ChatStatus {
    case empty
    case newSnap, newMessage
    case receivedSnap, receivedMessage
    case sentSnap, sentMessage
    case openedSnap, openedMessage

    var label: String {
        switch self {
        case .empty: return "Tippe zum Schreiben"
        case .newSnap: return "Neuer Snap"
        case .newMessage: return "Neue Nachricht"
        case .receivedSnap: return "Snap angesehen"
        case .receivedMessage: return "Empfangen"
        case .sentSnap, .sentMessage: return "Gesendet"
        case .openedSnap, .openedMessage: return "Geöffnet"
        }
    }

    var symbol: String {
        switch self {
        case .empty: return "bubble.left"
        case .newSnap: return "square.fill"
        case .newMessage: return "bubble.left.fill"
        case .receivedSnap: return "square"
        case .receivedMessage: return "bubble.left"
        case .sentSnap: return "paperplane.fill"
        case .sentMessage: return "paperplane.fill"
        case .openedSnap: return "paperplane"
        case .openedMessage: return "paperplane"
        }
    }

    var color: Color {
        switch self {
        case .empty: return .secondary
        case .newSnap, .receivedSnap, .sentSnap, .openedSnap: return Theme.snap
        case .newMessage, .receivedMessage, .sentMessage, .openedMessage: return Theme.chat
        }
    }

    var isUnread: Bool { self == .newSnap || self == .newMessage }
}

@MainActor
final class AppStore: ObservableObject {
    enum Phase { case loading, onboarding, ready }

    @Published var phase: Phase = .loading
    @Published private(set) var me: UserProfile?
    @Published private(set) var users: [String: UserProfile] = [:]
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var stories: [Story] = []

    // Navigation
    @Published var selectedTab: MainTab = .camera
    @Published var activeChat: ChatRoute?
    @Published var showProfile = false
    @Published var showAddFriend = false
    @Published var toast: String?

    let backend: ChatBackend

    private var profileToken: ListenerToken?
    private var conversationsToken: ListenerToken?
    private var usersToken: ListenerToken?
    private var storiesToken: ListenerToken?
    private var observedUserIDs: Set<String> = []
    private var observedStoryAuthors: Set<String> = []

    init(backend: ChatBackend) {
        self.backend = backend
    }

    /// Nimmt Firebase, wenn es eingerichtet ist – sonst den Demo-Modus.
    static func makeDefault() -> AppStore {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        if FirebaseBackend.isConfigured {
            return AppStore(backend: FirebaseBackend())
        }
        #endif
        return AppStore(backend: LocalBackend())
    }

    // MARK: - Abgeleitete Daten

    var friends: [UserProfile] {
        guard let me else { return [] }
        return me.friendIDs.compactMap { users[$0] }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func user(_ id: String) -> UserProfile? { users[id] }

    func otherParticipants(in conversation: Conversation) -> [UserProfile] {
        conversation.participantIDs.filter { $0 != me?.id }.compactMap { users[$0] }
    }

    func title(for conversation: Conversation) -> String {
        if let title = conversation.title, !title.isEmpty { return title }
        let names = otherParticipants(in: conversation).map(\.displayName)
        return names.isEmpty ? "Chat" : names.joined(separator: ", ")
    }

    /// Für das Avatar-Bild in der Chat-Liste: bei Gruppen ein Gruppen-Profil.
    func avatarUser(for conversation: Conversation) -> UserProfile? {
        if conversation.isGroup {
            return UserProfile(id: conversation.id, username: "", displayName: title(for: conversation),
                               emoji: "👨‍👩‍👧‍👦", colorHex: "8E7CFF")
        }
        return otherParticipants(in: conversation).first
    }

    func status(for conversation: Conversation) -> ChatStatus {
        guard let me, let sender = conversation.lastSenderID, let kind = conversation.lastMessageKind else {
            return .empty
        }
        let isSnap = kind == .snap
        if sender == me.id {
            let others = Set(conversation.participantIDs).subtracting([me.id])
            let opened = others.contains { conversation.readBy.contains($0) }
            if opened { return isSnap ? .openedSnap : .openedMessage }
            return isSnap ? .sentSnap : .sentMessage
        } else {
            let read = conversation.readBy.contains(me.id)
            if read { return isSnap ? .receivedSnap : .receivedMessage }
            return isSnap ? .newSnap : .newMessage
        }
    }

    var unreadCount: Int {
        conversations.filter { status(for: $0).isUnread }.count
    }

    /// Stories pro Person, neueste Person zuerst.
    struct StoryGroup: Identifiable {
        let author: UserProfile
        let stories: [Story]
        var id: String { author.id }
        var latest: Date { stories.last?.postedAt ?? .distantPast }
    }

    func storyGroups(includeMine: Bool) -> [StoryGroup] {
        let grouped = Dictionary(grouping: stories.filter { !$0.isExpired }, by: \.authorID)
        return grouped.compactMap { authorID, list -> StoryGroup? in
            guard let author = users[authorID] ?? (authorID == me?.id ? me : nil) else { return nil }
            if !includeMine && authorID == me?.id { return nil }
            return StoryGroup(author: author, stories: list.sorted { $0.postedAt < $1.postedAt })
        }
        .sorted { $0.latest > $1.latest }
    }

    var myStories: [Story] {
        stories.filter { $0.authorID == me?.id && !$0.isExpired }.sorted { $0.postedAt < $1.postedAt }
    }

    func hasUnviewedStories(_ group: StoryGroup) -> Bool {
        guard let me else { return false }
        return group.stories.contains { !$0.viewedBy.contains(me.id) }
    }

    // MARK: - Sitzung

    func bootstrap() async {
        guard phase == .loading else { return }
        if let profile = await backend.restoreSession() {
            startSession(profile)
        } else {
            phase = .onboarding
        }
    }

    func register(username: String, displayName: String, emoji: String, colorHex: String) async throws {
        let profile = try await backend.register(username: username, displayName: displayName,
                                                 emoji: emoji, colorHex: colorHex)
        startSession(profile)
    }

    private func startSession(_ profile: UserProfile) {
        me = profile
        users[profile.id] = profile
        selectedTab = .camera
        phase = .ready

        profileToken = backend.observeProfile(userID: profile.id) { [weak self] updated in
            guard let self else { return }
            self.me = updated
            self.users[updated.id] = updated
            self.refreshObservers()
        }
        conversationsToken = backend.observeConversations(userID: profile.id) { [weak self] list in
            guard let self else { return }
            self.conversations = list.sorted { $0.lastActivity > $1.lastActivity }
            self.refreshObservers()
        }
        refreshObservers()
    }

    /// Beobachtet alle Personen, die in Freundesliste oder Chats vorkommen, und deren Stories.
    private func refreshObservers() {
        guard let me else { return }

        var ids = Set(me.friendIDs)
        for conversation in conversations { ids.formUnion(conversation.participantIDs) }
        ids.remove(me.id)
        if ids != observedUserIDs {
            observedUserIDs = ids
            usersToken?.cancel()
            usersToken = backend.observeUsers(ids: ids.sorted()) { [weak self] list in
                guard let self else { return }
                var map: [String: UserProfile] = [:]
                for user in list { map[user.id] = user }
                if let me = self.me { map[me.id] = me }
                self.users = map
            }
        }

        let authors = Set(me.friendIDs + [me.id])
        if authors != observedStoryAuthors {
            observedStoryAuthors = authors
            storiesToken?.cancel()
            storiesToken = backend.observeStories(authorIDs: authors.sorted()) { [weak self] list in
                self?.stories = list
            }
        }
    }

    func signOut() {
        [profileToken, conversationsToken, usersToken, storiesToken].forEach { $0?.cancel() }
        profileToken = nil; conversationsToken = nil; usersToken = nil; storiesToken = nil
        observedUserIDs = []
        observedStoryAuthors = []
        backend.signOut()
        me = nil
        users = [:]
        conversations = []
        stories = []
        activeChat = nil
        showProfile = false
        phase = .onboarding
    }

    func updateProfile(displayName: String, emoji: String, colorHex: String) async {
        guard var profile = me else { return }
        profile.displayName = displayName
        profile.emoji = emoji
        profile.colorHex = colorHex
        me = profile
        users[profile.id] = profile
        await perform { try await self.backend.updateProfile(profile) }
    }

    // MARK: - Freunde

    @discardableResult
    func addFriend(username: String) async throws -> UserProfile {
        guard let me else { throw BackendError.notSignedIn }
        let name = username.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        return try await backend.addFriend(username: name, to: me)
    }

    func removeFriend(_ friend: UserProfile) async {
        guard let me else { return }
        await perform { try await self.backend.removeFriend(friend.id, from: me) }
    }

    // MARK: - Chats

    func openChat(with participantIDs: [String], title: String? = nil) async {
        guard let me else { return }
        do {
            let conversation = try await backend.openConversation(participants: participantIDs + [me.id], title: title)
            activeChat = ChatRoute(id: conversation.id)
        } catch {
            showError(error)
        }
    }

    func conversation(id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func sendText(_ text: String, in conversation: Conversation) async {
        guard let me else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = Message(conversationID: conversation.id, senderID: me.id, kind: .text, text: trimmed)
        await perform { try await self.backend.send(message, in: conversation) }
    }

    /// Schickt einen Snap an Freunde, Gruppen und/oder die eigene Story.
    func sendSnap(_ image: UIImage,
                  duration: Int?,
                  toFriends friendIDs: [String],
                  toConversations conversationIDs: [String],
                  toStory: Bool) async -> Bool {
        guard let me else { return false }
        guard let data = ImageTools.jpegData(image) else {
            showError(BackendError.imageEncodingFailed)
            return false
        }
        do {
            for friendID in friendIDs {
                let conversation = try await backend.openConversation(participants: [me.id, friendID], title: nil)
                try await backend.send(makeSnap(data, duration: duration, in: conversation.id, from: me.id), in: conversation)
            }
            for id in conversationIDs {
                guard let conversation = self.conversation(id: id) else { continue }
                try await backend.send(makeSnap(data, duration: duration, in: id, from: me.id), in: conversation)
            }
            if toStory {
                try await backend.postStory(Story(authorID: me.id, imageData: data))
            }
            let count = friendIDs.count + conversationIDs.count
            if toStory && count == 0 {
                toast = "Zu deiner Story hinzugefügt ✨"
            } else {
                toast = "Snap gesendet 🚀"
            }
            return true
        } catch {
            showError(error)
            return false
        }
    }

    private func makeSnap(_ data: Data, duration: Int?, in conversationID: String, from sender: String) -> Message {
        Message(conversationID: conversationID, senderID: sender, kind: .snap, imageData: data, snapDuration: duration)
    }

    func markRead(_ conversation: Conversation) async {
        guard let me, !conversation.readBy.contains(me.id) else { return }
        await perform { try await self.backend.markConversationRead(conversation.id, by: me.id) }
    }

    func markSnapViewed(_ message: Message, in conversation: Conversation) async {
        guard let me else { return }
        await perform { try await self.backend.markSnapViewed(message, by: me.id, in: conversation) }
    }

    func delete(_ message: Message) async {
        await perform { try await self.backend.deleteMessage(message) }
    }

    // MARK: - Stories

    func markStoryViewed(_ story: Story) async {
        guard let me, !story.viewedBy.contains(me.id), story.authorID != me.id else { return }
        await perform { try await self.backend.markStoryViewed(story, by: me.id) }
    }

    func deleteStory(_ story: Story) async {
        await perform { try await self.backend.deleteStory(story) }
    }

    // MARK: - Hilfen

    private func perform(_ work: @escaping () async throws -> Void) async {
        do { try await work() } catch { showError(error) }
    }

    func showError(_ error: Error) {
        toast = "⚠️ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}
