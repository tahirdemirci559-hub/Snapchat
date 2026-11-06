#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Online-Modus über Firebase (Auth + Firestore).
/// Wird automatisch benutzt, sobald das Firebase-Paket eingebunden ist und
/// eine `GoogleService-Info.plist` im Projekt liegt (siehe README).
@MainActor
final class FirebaseBackend: ChatBackend {
    var modeDescription: String { "Online (Firebase)" }
    var isDemo: Bool { false }

    static var isConfigured: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    private let db: Firestore

    init() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        db = Firestore.firestore()
    }

    private var users: CollectionReference { db.collection("users") }
    private var conversations: CollectionReference { db.collection("conversations") }
    private var stories: CollectionReference { db.collection("stories") }
    private func messages(_ conversationID: String) -> CollectionReference {
        conversations.document(conversationID).collection("messages")
    }

    // MARK: - Konto

    func restoreSession() async -> UserProfile? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        do {
            let snapshot = try await users.document(uid).getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: UserProfile.self)
        } catch {
            print("Pling: Profil konnte nicht geladen werden: \(error)")
            return nil
        }
    }

    func register(username: String, displayName: String, emoji: String, colorHex: String) async throws -> UserProfile {
        let name = username.lowercased()
        guard UserProfile.isValidUsername(name) else { throw BackendError.invalidUsername }

        let uid: String
        if let current = Auth.auth().currentUser {
            uid = current.uid
        } else {
            uid = try await Auth.auth().signInAnonymously().user.uid
        }

        let existing = try await users.whereField("username", isEqualTo: name).limit(to: 1).getDocuments()
        if let doc = existing.documents.first, doc.documentID != uid {
            throw BackendError.usernameTaken
        }

        let profile = UserProfile(id: uid, username: name, displayName: displayName,
                                  emoji: emoji, colorHex: colorHex)
        try users.document(uid).setData(from: profile)
        return profile
    }

    func updateProfile(_ profile: UserProfile) async throws {
        try await users.document(profile.id).updateData([
            "displayName": profile.displayName,
            "emoji": profile.emoji,
            "colorHex": profile.colorHex
        ])
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Beobachten

    func observeProfile(userID: String, onChange: @escaping (UserProfile) -> Void) -> ListenerToken {
        let registration = users.document(userID).addSnapshotListener { snapshot, _ in
            guard let snapshot, let profile = try? snapshot.data(as: UserProfile.self) else { return }
            Task { @MainActor in onChange(profile) }
        }
        return ListenerToken { registration.remove() }
    }

    func observeUsers(ids: [String], onChange: @escaping ([UserProfile]) -> Void) -> ListenerToken {
        observeChunked(values: ids,
                       makeQuery: { chunk in self.users.whereField(FieldPath.documentID(), in: chunk) },
                       onChange: onChange)
    }

    func observeConversations(userID: String, onChange: @escaping ([Conversation]) -> Void) -> ListenerToken {
        let registration = conversations
            .whereField("participantIDs", arrayContains: userID)
            .addSnapshotListener { snapshot, error in
                if let error { print("Pling: Chats-Fehler: \(error)") }
                let list = snapshot?.documents.compactMap { try? $0.data(as: Conversation.self) } ?? []
                Task { @MainActor in onChange(list) }
            }
        return ListenerToken { registration.remove() }
    }

    func observeMessages(conversationID: String, onChange: @escaping ([Message]) -> Void) -> ListenerToken {
        let registration = messages(conversationID)
            .order(by: "sentAt")
            .addSnapshotListener { snapshot, error in
                if let error { print("Pling: Nachrichten-Fehler: \(error)") }
                let list = snapshot?.documents.compactMap { try? $0.data(as: Message.self) } ?? []
                Task { @MainActor in onChange(list) }
            }
        return ListenerToken { registration.remove() }
    }

    func observeStories(authorIDs: [String], onChange: @escaping ([Story]) -> Void) -> ListenerToken {
        observeChunked(values: authorIDs,
                       makeQuery: { chunk in self.stories.whereField("authorID", in: chunk) },
                       onChange: { (list: [Story]) in onChange(list.filter { !$0.isExpired }) })
    }

    /// Firestore erlaubt bei `in`-Abfragen max. 30 Werte – daher in Blöcke aufteilen.
    private final class ChunkBox<T> {
        var parts: [Int: [T]] = [:]
    }

    private func observeChunked<T: Decodable>(values: [String],
                                             makeQuery: ([String]) -> Query,
                                             onChange: @escaping ([T]) -> Void) -> ListenerToken {
        guard !values.isEmpty else {
            onChange([])
            return .empty
        }
        let box = ChunkBox<T>()
        let chunks = stride(from: 0, to: values.count, by: 30).map { Array(values[$0..<min($0 + 30, values.count)]) }
        let registrations: [ListenerRegistration] = chunks.enumerated().map { index, chunk in
            makeQuery(chunk).addSnapshotListener { snapshot, error in
                if let error { print("Pling: Abfrage-Fehler: \(error)") }
                let list = snapshot?.documents.compactMap { try? $0.data(as: T.self) } ?? []
                Task { @MainActor in
                    box.parts[index] = list
                    onChange(box.parts.keys.sorted().flatMap { box.parts[$0] ?? [] })
                }
            }
        }
        return ListenerToken { registrations.forEach { $0.remove() } }
    }

    // MARK: - Freunde

    func addFriend(username: String, to me: UserProfile) async throws -> UserProfile {
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
        let result = try await users.whereField("username", isEqualTo: name).limit(to: 1).getDocuments()
        guard let doc = result.documents.first else { throw BackendError.userNotFound }
        let friend = try doc.data(as: UserProfile.self)
        guard friend.id != me.id else { throw BackendError.cannotAddSelf }
        guard !me.friendIDs.contains(friend.id) else { throw BackendError.alreadyFriends }

        let batch = db.batch()
        batch.updateData(["friendIDs": FieldValue.arrayUnion([friend.id])], forDocument: users.document(me.id))
        batch.updateData(["friendIDs": FieldValue.arrayUnion([me.id])], forDocument: users.document(friend.id))
        try await batch.commit()
        return friend
    }

    func removeFriend(_ friendID: String, from me: UserProfile) async throws {
        let batch = db.batch()
        batch.updateData(["friendIDs": FieldValue.arrayRemove([friendID])], forDocument: users.document(me.id))
        batch.updateData(["friendIDs": FieldValue.arrayRemove([me.id])], forDocument: users.document(friendID))
        try await batch.commit()
    }

    // MARK: - Chats

    func openConversation(participants: [String], title: String?) async throws -> Conversation {
        let conversation = Conversation.new(participants: participants, title: title)
        let ref = conversations.document(conversation.id)
        let snapshot = try await ref.getDocument()
        if snapshot.exists, let existing = try? snapshot.data(as: Conversation.self) {
            return existing
        }
        try ref.setData(from: conversation)
        return conversation
    }

    func send(_ message: Message, in conversation: Conversation) async throws {
        let convRef = conversations.document(conversation.id)
        let latest = (try? await convRef.getDocument().data(as: Conversation.self)) ?? conversation
        let batch = db.batch()
        try batch.setData(from: message, forDocument: messages(conversation.id).document(message.id))
        try batch.setData(from: latest.applying(message), forDocument: convRef)
        try await batch.commit()
    }

    func markConversationRead(_ conversationID: String, by userID: String) async throws {
        try await conversations.document(conversationID).updateData([
            "readBy": FieldValue.arrayUnion([userID])
        ])
    }

    func markSnapViewed(_ message: Message, by userID: String, in conversation: Conversation) async throws {
        var update: [String: Any] = ["viewedBy": FieldValue.arrayUnion([userID])]
        let viewers = Set(message.viewedBy + [userID])
        let recipients = Set(conversation.participantIDs).subtracting([message.senderID])
        if recipients.isSubset(of: viewers) {
            update["imageData"] = FieldValue.delete()   // Snap verschwindet nach dem Ansehen
        }
        let batch = db.batch()
        batch.updateData(update, forDocument: messages(conversation.id).document(message.id))
        batch.updateData(["readBy": FieldValue.arrayUnion([userID])], forDocument: conversations.document(conversation.id))
        try await batch.commit()
    }

    func deleteMessage(_ message: Message) async throws {
        try await messages(message.conversationID).document(message.id).delete()
    }

    // MARK: - Stories

    func postStory(_ story: Story) async throws {
        try stories.document(story.id).setData(from: story)
    }

    func markStoryViewed(_ story: Story, by userID: String) async throws {
        try await stories.document(story.id).updateData(["viewedBy": FieldValue.arrayUnion([userID])])
    }

    func deleteStory(_ story: Story) async throws {
        try await stories.document(story.id).delete()
    }
}
#endif
