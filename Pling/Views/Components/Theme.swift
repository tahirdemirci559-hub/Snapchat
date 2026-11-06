import SwiftUI

enum Theme {
    static let brand = Color(hex: "7B5CFF")
    static let brandPink = Color(hex: "FF5CAA")
    static let snap = Color(hex: "9B5CFF")
    static let chat = Color(hex: "1FB8C8")
    static let streak = Color(hex: "FF8A3D")

    static let gradient = LinearGradient(colors: [Color(hex: "9B5CFF"), Color(hex: "FF5CAA")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    static let avatarColors = ["7B5CFF", "FF5CAA", "FF6FA5", "3FA9F5", "1FB8C8", "38C98B", "FFB938", "FF8A3D", "F25555", "5E6AD2"]
    static let avatarEmojis = ["😀", "😎", "🥳", "🤓", "😺", "🐶", "🦊", "🐼", "🦄", "🐸", "👩", "👨", "👧", "👦", "👵", "👴", "🧑‍🚀", "🧙", "⚽️", "🎸", "🌸", "🍕", "🚀", "🌈"]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Date {
    /// Kurze Zeitangabe wie bei Chat-Apps: „jetzt“, „5 Min.“, „3 Std.“, „2 T.“
    var shortAgo: String {
        let seconds = Int(Date().timeIntervalSince(self))
        switch seconds {
        case ..<60: return "jetzt"
        case ..<3600: return "\(seconds / 60) Min."
        case ..<86_400: return "\(seconds / 3600) Std."
        case ..<(7 * 86_400): return "\(seconds / 86_400) T."
        default: return formatted(.dateTime.day().month(.abbreviated))
        }
    }
}

struct AvatarView: View {
    let user: UserProfile?
    var size: CGFloat = 44
    var ring: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: user?.colorHex ?? "BBBBBB").gradient)
            Text(user?.emoji ?? "🙂")
                .font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
        .padding(ring ? 3 : 0)
        .overlay {
            if ring {
                Circle().strokeBorder(Theme.gradient, lineWidth: 3)
            }
        }
    }
}

struct StreakBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Text("\(count)")
                    .font(.caption.bold())
                Text("🔥")
                    .font(.caption)
            }
            .foregroundStyle(Theme.streak)
        }
    }
}

/// Kleiner Hinweis, der kurz am oberen Rand erscheint.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial, in: Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { self.message = nil }
                    }
                    .onTapGesture { withAnimation { self.message = nil } }
            }
        }
        .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// Kopfzeile für die Seiten „Chats“ und „Stories“.
struct PageHeader<Trailing: View>: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.showProfile = true
            } label: {
                AvatarView(user: store.me, size: 38)
            }
            .accessibilityLabel("Profil")

            Button {
                store.showAddFriend = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Freunde hinzufügen")

            Spacer()
            Text(title)
                .font(.title2.bold())
            Spacer()

            trailing()
                .frame(minWidth: 88, alignment: .trailing)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
