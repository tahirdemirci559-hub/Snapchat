import Foundation

// MARK: - Benutzer

struct UserProfile: Codable, Identifiable, Hashable {
    var id: String
    var username: String
    var displayName: String
    var emoji: String
    var colorHex: String
    var friendIDs: [String]
    var createdAt: Date

    init(id: String,
         username: String,
         displayName: String,
         emoji: String,
         colorHex: String,
         friendIDs: [String] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.emoji = emoji
        self.colorHex = colorHex
        self.friendIDs = friendIDs
        self.createdAt = createdAt
    }

    /// Benutzernamen: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich.
    static func isValidUsername(_ name: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._")
        return (3...20).contains(name.count) && name.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Nachrichten

enum MessageKind: String, Codable {
    case text
    case snap
}

struct Message: Codable, Identifiable, Hashable {
    var id: String
    var conversationID: String
    var senderID: String
    var kind: MessageKind
    var text: String?
    /// JPEG-Daten eines Snaps. Wird gelöscht, sobald alle Empfänger den Snap angesehen haben.
    var imageData: Data?
    /// Anzeigedauer eines Snaps in Sekunden (`nil` = unbegrenzt, bis man tippt).
    var snapDuration: Int?
    var sentAt: Date
    var viewedBy: [String]

    init(id: String = UUID().uuidString,
         conversationID: String,
         senderID: String,
         kind: MessageKind,
         text: String? = nil,
         imageData: Data? = nil,
         snapDuration: Int? = nil,
         sentAt: Date = Date(),
         viewedBy: [String] = []) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.snapDuration = snapDuration
        self.sentAt = sentAt
        self.viewedBy = viewedBy
    }

    var previewText: String {
        switch kind {
        case .text: return text ?? ""
        case .snap: return "📸 Snap"
        }
    }
}

// MARK: - Unterhaltungen

struct Conversation: Codable, Identifiable, Hashable {
    var id: String
    var participantIDs: [String]
    /// Nur bei Gruppen gesetzt.
    var title: String?
    var lastMessageKind: MessageKind?
    var lastSenderID: String?
    var lastMessageText: String?
    var lastActivity: Date
    /// Wer die letzte Nachricht schon gesehen hat.
    var readBy: [String]
    /// 🔥 Flammen-Serie: an wie vielen Tagen in Folge geschrieben wurde.
    var streak: Int
    var streakDay: String?

    var isGroup: Bool { participantIDs.count > 2 || title != nil }

    /// Für 1:1-Chats gibt es immer genau eine ID, egal wer den Chat startet.
    static func directID(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    static func new(participants: [String], title: String?) -> Conversation {
        let unique = Array(Set(participants)).sorted()
        let id = (unique.count == 2 && title == nil)
            ? directID(unique[0], unique[1])
            : UUID().uuidString
        return Conversation(id: id,
                            participantIDs: unique,
                            title: title,
                            lastMessageKind: nil,
                            lastSenderID: nil,
                            lastMessageText: nil,
                            lastActivity: Date(),
                            readBy: [],
                            streak: 0,
                            streakDay: nil)
    }

    /// Aktualisiert Vorschau, Gelesen-Status und Flammen-Serie nach einer neuen Nachricht.
    func applying(_ message: Message) -> Conversation {
        var copy = self
        copy.lastMessageKind = message.kind
        copy.lastSenderID = message.senderID
        copy.lastMessageText = message.kind == .text ? message.text : nil
        copy.lastActivity = message.sentAt
        copy.readBy = [message.senderID]

        let today = Self.dayString(message.sentAt)
        if copy.streakDay != today {
            let yesterday = Self.dayString(message.sentAt.addingTimeInterval(-86_400))
            copy.streak = (copy.streakDay == yesterday) ? copy.streak + 1 : 1
            copy.streakDay = today
        }
        return copy
    }

    /// Die Serie zählt nur, wenn heute oder gestern geschrieben wurde.
    var activeStreak: Int {
        guard let streakDay else { return 0 }
        let now = Date()
        if streakDay == Self.dayString(now) || streakDay == Self.dayString(now.addingTimeInterval(-86_400)) {
            return streak
        }
        return 0
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
}

// MARK: - Stories

struct Story: Codable, Identifiable, Hashable {
    var id: String
    var authorID: String
    var imageData: Data
    var postedAt: Date
    var viewedBy: [String]

    init(id: String = UUID().uuidString,
         authorID: String,
         imageData: Data,
         postedAt: Date = Date(),
         viewedBy: [String] = []) {
        self.id = id
        self.authorID = authorID
        self.imageData = imageData
        self.postedAt = postedAt
        self.viewedBy = viewedBy
    }

    /// Stories verschwinden nach 24 Stunden.
    static let lifetime: TimeInterval = 24 * 3600
    var isExpired: Bool { Date().timeIntervalSince(postedAt) > Self.lifetime }
}
