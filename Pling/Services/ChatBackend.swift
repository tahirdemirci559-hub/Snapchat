import Foundation

/// Wird von den `observe…`-Funktionen zurückgegeben. `cancel()` beendet das Beobachten.
@MainActor
final class ListenerToken {
    private var onCancel: (() -> Void)?

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    static var empty: ListenerToken { ListenerToken {} }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

enum BackendError: LocalizedError {
    case invalidUsername
    case usernameTaken
    case userNotFound
    case cannotAddSelf
    case alreadyFriends
    case notSignedIn
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidUsername: return "Der Benutzername muss 3–20 Zeichen lang sein (nur a–z, 0–9, Punkt, Unterstrich)."
        case .usernameTaken: return "Dieser Benutzername ist schon vergeben."
        case .userNotFound: return "Niemanden mit diesem Benutzernamen gefunden."
        case .cannotAddSelf: return "Du kannst dich nicht selbst hinzufügen. 😄"
        case .alreadyFriends: return "Ihr seid schon befreundet."
        case .notSignedIn: return "Du bist nicht angemeldet."
        case .imageEncodingFailed: return "Das Bild konnte nicht verarbeitet werden."
        }
    }
}

/// Die App spricht nur über dieses Protokoll mit dem Server.
/// - `LocalBackend`: Demo-Modus, alles bleibt auf dem Gerät (mit Demo-Freunden, die antworten).
/// - `FirebaseBackend`: echter Online-Modus, um mit Familie und Freunden zu schreiben.
@MainActor
protocol ChatBackend: AnyObject {
    var modeDescription: String { get }
    var isDemo: Bool { get }

    func restoreSession() async -> UserProfile?
    func register(username: String, displayName: String, emoji: String, colorHex: String) async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
    func signOut()

    func observeProfile(userID: String, onChange: @escaping (UserProfile) -> Void) -> ListenerToken
    func observeUsers(ids: [String], onChange: @escaping ([UserProfile]) -> Void) -> ListenerToken
    func observeConversations(userID: String, onChange: @escaping ([Conversation]) -> Void) -> ListenerToken
    func observeMessages(conversationID: String, onChange: @escaping ([Message]) -> Void) -> ListenerToken
    func observeStories(authorIDs: [String], onChange: @escaping ([Story]) -> Void) -> ListenerToken

    func addFriend(username: String, to me: UserProfile) async throws -> UserProfile
    func removeFriend(_ friendID: String, from me: UserProfile) async throws

    func openConversation(participants: [String], title: String?) async throws -> Conversation
    func send(_ message: Message, in conversation: Conversation) async throws
    func markConversationRead(_ conversationID: String, by userID: String) async throws
    func markSnapViewed(_ message: Message, by userID: String, in conversation: Conversation) async throws
    func deleteMessage(_ message: Message) async throws

    func postStory(_ story: Story) async throws
    func markStoryViewed(_ story: Story, by userID: String) async throws
    func deleteStory(_ story: Story) async throws
}
