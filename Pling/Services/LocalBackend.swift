import UIKit

/// Demo-Modus: Alle Daten liegen als JSON-Datei auf dem Gerät.
/// Mama, Papa, Lena und Opa sind Demo-Freunde, die automatisch antworten,
/// damit man alle Funktionen sofort ausprobieren kann.
@MainActor
final class LocalBackend: ChatBackend {
    private struct State: Codable {
        var currentUserID: String?
        var users: [String: UserProfile] = [:]
        var conversations: [String: Conversation] = [:]
        var messages: [String: [Message]] = [:]
        var stories: [Story] = []
    }

    var modeDescription: String { "Demo-Modus (nur auf diesem Gerät)" }
    var isDemo: Bool { true }

    private var state = State()
    private var observers: [UUID: () -> Void] = [:]
    private let fileURL: URL

    private static let demoUsers: [UserProfile] = [
        UserProfile(id: "demo-mama", username: "mama", displayName: "Mama", emoji: "👩", colorHex: "FF6FA5"),
        UserProfile(id: "demo-papa", username: "papa", displayName: "Papa", emoji: "👨", colorHex: "3FA9F5"),
        UserProfile(id: "demo-lena", username: "lena", displayName: "Lena", emoji: "👧", colorHex: "FFB938"),
        UserProfile(id: "demo-opa", username: "opa", displayName: "Opa", emoji: "👴", colorHex: "38C98B")
    ]

    private static let replies = [
        "Haha, super! 😂", "Oh wie schön! ❤️", "Bin gleich da 🏃", "Was gibt's zum Essen? 🍝",
        "Hab dich lieb! 🥰", "Wow 😍", "Ok 👍", "Erzähl mehr!", "Sehen wir uns am Wochenende?",
        "Ich vermisse dich 🤗", "Lol 🤣", "Das ist ja lustig!"
    ]

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("pling-demo.json")
        load()
    }

    // MARK: - Speichern & Laden

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(State.self, from: data) else { return }
        state = decoded
        state.stories.removeAll { $0.isExpired }
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
        for id in Array(observers.keys) {
            observers[id]?()
        }
    }

    private func addObserver(_ refresh: @escaping () -> Void) -> ListenerToken {
        let id = UUID()
        observers[id] = refresh
        refresh()
        return ListenerToken { [weak self] in
            self?.observers[id] = nil
        }
    }

    // MARK: - Konto

    func restoreSession() async -> UserProfile? {
        guard let id = state.currentUserID else { return nil }
        return state.users[id]
    }

    func register(username: String, displayName: String, emoji: String, colorHex: String) async throws -> UserProfile {
        let name = username.lowercased()
        guard UserProfile.isValidUsername(name) else { throw BackendError.invalidUsername }
        if state.users.values.contains(where: { $0.username == name }) { throw BackendError.usernameTaken }

        let me = UserProfile(id: UUID().uuidString, username: name, displayName: displayName,
                             emoji: emoji, colorHex: colorHex)
        state.users[me.id] = me
        state.currentUserID = me.id
        seedDemoData(for: me)
        commit()
        return state.users[me.id] ?? me
    }

    func updateProfile(_ profile: UserProfile) async throws {
        state.users[profile.id] = profile
        commit()
    }

    func signOut() {
        state.currentUserID = nil
        commit()
    }

    // MARK: - Beobachten

    func observeProfile(userID: String, onChange: @escaping (UserProfile) -> Void) -> ListenerToken {
        addObserver { [weak self] in
            if let user = self?.state.users[userID] { onChange(user) }
        }
    }

    func observeUsers(ids: [String], onChange: @escaping ([UserProfile]) -> Void) -> ListenerToken {
        addObserver { [weak self] in
            guard let self else { return }
            onChange(ids.compactMap { self.state.users[$0] })
        }
    }

    func observeConversations(userID: String, onChange: @escaping ([Conversation]) -> Void) -> ListenerToken {
        addObserver { [weak self] in
            guard let self else { return }
            onChange(self.state.conversations.values.filter { $0.participantIDs.contains(userID) })
        }
    }

    func observeMessages(conversationID: String, onChange: @escaping ([Message]) -> Void) -> ListenerToken {
        addObserver { [weak self] in
            guard let self else { return }
            onChange((self.state.messages[conversationID] ?? []).sorted { $0.sentAt < $1.sentAt })
        }
    }

    func observeStories(authorIDs: [String], onChange: @escaping ([Story]) -> Void) -> ListenerToken {
        let authors = Set(authorIDs)
        return addObserver { [weak self] in
            guard let self else { return }
            onChange(self.state.stories.filter { authors.contains($0.authorID) && !$0.isExpired })
        }
    }

    // MARK: - Freunde

    func addFriend(username: String, to me: UserProfile) async throws -> UserProfile {
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
        guard let friend = state.users.values.first(where: { $0.username == name }) else {
            throw BackendError.userNotFound
        }
        guard friend.id != me.id else { throw BackendError.cannotAddSelf }
        guard var current = state.users[me.id] else { throw BackendError.notSignedIn }
        guard !current.friendIDs.contains(friend.id) else { throw BackendError.alreadyFriends }

        current.friendIDs.append(friend.id)
        state.users[me.id] = current
        if var other = state.users[friend.id], !other.friendIDs.contains(me.id) {
            other.friendIDs.append(me.id)
            state.users[friend.id] = other
        }
        commit()
        return friend
    }

    func removeFriend(_ friendID: String, from me: UserProfile) async throws {
        state.users[me.id]?.friendIDs.removeAll { $0 == friendID }
        state.users[friendID]?.friendIDs.removeAll { $0 == me.id }
        commit()
    }

    // MARK: - Chats

    func openConversation(participants: [String], title: String?) async throws -> Conversation {
        let conversation = Conversation.new(participants: participants, title: title)
        if let existing = state.conversations[conversation.id] { return existing }
        state.conversations[conversation.id] = conversation
        commit()
        return conversation
    }

    func send(_ message: Message, in conversation: Conversation) async throws {
        let current = state.conversations[conversation.id] ?? conversation
        state.conversations[conversation.id] = current.applying(message)
        state.messages[conversation.id, default: []].append(message)
        commit()
        scheduleDemoReaction(to: message, in: conversation.id)
    }

    func markConversationRead(_ conversationID: String, by userID: String) async throws {
        guard var conversation = state.conversations[conversationID],
              !conversation.readBy.contains(userID) else { return }
        conversation.readBy.append(userID)
        state.conversations[conversationID] = conversation
        commit()
    }

    func markSnapViewed(_ message: Message, by userID: String, in conversation: Conversation) async throws {
        guard var list = state.messages[conversation.id],
              let index = list.firstIndex(where: { $0.id == message.id }) else { return }
        if !list[index].viewedBy.contains(userID) { list[index].viewedBy.append(userID) }

        let recipients = Set(conversation.participantIDs).subtracting([message.senderID])
        if recipients.isSubset(of: Set(list[index].viewedBy)) {
            list[index].imageData = nil   // Snap verschwindet nach dem Ansehen
        }
        state.messages[conversation.id] = list
        if var conv = state.conversations[conversation.id], !conv.readBy.contains(userID) {
            conv.readBy.append(userID)
            state.conversations[conversation.id] = conv
        }
        commit()
    }

    func deleteMessage(_ message: Message) async throws {
        state.messages[message.conversationID]?.removeAll { $0.id == message.id }
        commit()
    }

    // MARK: - Stories

    func postStory(_ story: Story) async throws {
        state.stories.append(story)
        commit()
    }

    func markStoryViewed(_ story: Story, by userID: String) async throws {
        guard let index = state.stories.firstIndex(where: { $0.id == story.id }),
              !state.stories[index].viewedBy.contains(userID) else { return }
        state.stories[index].viewedBy.append(userID)
        commit()
    }

    func deleteStory(_ story: Story) async throws {
        state.stories.removeAll { $0.id == story.id }
        commit()
    }

    // MARK: - Demo-Daten

    private func seedDemoData(for me: UserProfile) {
        for var demo in Self.demoUsers where state.users[demo.id] == nil {
            demo.friendIDs = []
            state.users[demo.id] = demo
        }
        // Mama, Papa und Lena sind schon Freunde – Opa kann man selbst hinzufügen (Benutzername „opa“).
        let initialFriends = ["demo-mama", "demo-papa", "demo-lena"]
        state.users[me.id]?.friendIDs = initialFriends
        for id in initialFriends {
            state.users[id]?.friendIDs.append(me.id)
        }

        let welcome = Conversation.new(participants: [me.id, "demo-mama"], title: nil)
        let hello = Message(conversationID: welcome.id, senderID: "demo-mama", kind: .text,
                            text: "Hallo \(me.displayName)! Willkommen bei Pling 💜 Schick mir doch mal einen Snap!",
                            sentAt: Date().addingTimeInterval(-600))
        state.conversations[welcome.id] = welcome.applying(hello)
        state.messages[welcome.id] = [hello]

        let family = Conversation.new(participants: [me.id, "demo-mama", "demo-papa", "demo-lena"], title: "Familie 🏡")
        let papa = Message(conversationID: family.id, senderID: "demo-papa", kind: .text,
                           text: "Wer kommt Sonntag zum Grillen? 🍖", sentAt: Date().addingTimeInterval(-3600))
        state.conversations[family.id] = family.applying(papa)
        state.messages[family.id] = [papa]

        let lenaChat = Conversation.new(participants: [me.id, "demo-lena"], title: nil)
        if let data = ImageTools.jpegData(ImageTools.demoImage(
            emoji: "🐶", text: "Schau mal, ein Hund!",
            colors: [UIColor(red: 1, green: 0.73, blue: 0.22, alpha: 1), UIColor(red: 1, green: 0.42, blue: 0.42, alpha: 1)])) {
            let snap = Message(conversationID: lenaChat.id, senderID: "demo-lena", kind: .snap,
                               imageData: data, snapDuration: 5, sentAt: Date().addingTimeInterval(-120))
            state.conversations[lenaChat.id] = lenaChat.applying(snap)
            state.messages[lenaChat.id] = [snap]
        }

        let storyImages: [(String, String, String, [UIColor])] = [
            ("demo-lena", "🏖️", "Ferien!", [.systemTeal, .systemBlue]),
            ("demo-papa", "🚴", "Morgenrunde ✅", [.systemGreen, .systemTeal]),
            ("demo-mama", "🎂", "Kuchen ist fertig!", [.systemPink, .systemPurple])
        ]
        for (index, item) in storyImages.enumerated() {
            if let data = ImageTools.jpegData(ImageTools.demoImage(emoji: item.1, text: item.2, colors: item.3)) {
                state.stories.append(Story(authorID: item.0, imageData: data,
                                           postedAt: Date().addingTimeInterval(TimeInterval(-1800 * (index + 1)))))
            }
        }
    }

    /// Demo-Freunde „öffnen“ Snaps und antworten nach ein paar Sekunden.
    private func scheduleDemoReaction(to message: Message, in conversationID: String) {
        guard let conversation = state.conversations[conversationID] else { return }
        let demoIDs = conversation.participantIDs.filter { $0.hasPrefix("demo-") && $0 != message.senderID }
        guard let responder = demoIDs.randomElement(), !message.senderID.hasPrefix("demo-") else { return }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, let conv = self.state.conversations[conversationID] else { return }
            if message.kind == .snap {
                try? await self.markSnapViewed(message, by: responder, in: conv)
            } else {
                try? await self.markConversationRead(conversationID, by: responder)
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let latest = self.state.conversations[conversationID] else { return }
            let text = message.kind == .snap
                ? ["Toller Snap! 😍", "Hahaha 😂", "Wie süß! 🥹", "Wo bist du da? 👀"].randomElement()!
                : Self.replies.randomElement()!
            let reply = Message(conversationID: conversationID, senderID: responder, kind: .text, text: text)
            self.state.conversations[conversationID] = latest.applying(reply)
            self.state.messages[conversationID, default: []].append(reply)
            self.commit()
        }
    }
}
