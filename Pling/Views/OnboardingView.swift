import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    @State private var displayName = ""
    @State private var username = ""
    @State private var emoji = Theme.avatarEmojis.randomElement() ?? "😀"
    @State private var colorHex = Theme.avatarColors.randomElement() ?? "7B5CFF"
    @State private var isLoading = false
    @State private var errorText: String?

    private var cleanedUsername: String {
        username.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && UserProfile.isValidUsername(cleanedUsername)
            && !isLoading
    }

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        LogoView(size: 84)
                        Text("Pling")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Snaps, Chats & Stories mit Familie und Freunden.")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Spacer()
                            AvatarView(user: preview, size: 88)
                            Spacer()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Theme.avatarEmojis, id: \.self) { item in
                                    Button {
                                        emoji = item
                                    } label: {
                                        Text(item)
                                            .font(.system(size: 28))
                                            .frame(width: 46, height: 46)
                                            .background(emoji == item ? Color(hex: colorHex).opacity(0.3) : Color(.secondarySystemBackground),
                                                        in: Circle())
                                    }
                                }
                            }
                        }

                        ColorRow(selection: $colorHex)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dein Name").font(.subheadline.bold())
                            TextField("z. B. Tahir", text: $displayName)
                                .textContentType(.givenName)
                                .padding(12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Benutzername").font(.subheadline.bold())
                            HStack {
                                Text("@").foregroundStyle(.secondary)
                                TextField("benutzername", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text("Damit finden dich deine Freunde. 3–20 Zeichen: a–z, 0–9, . und _")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await register() }
                        } label: {
                            HStack {
                                if isLoading { ProgressView().tint(.white) }
                                Text("Los geht's")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canContinue ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.gray.opacity(0.4)),
                                        in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .disabled(!canContinue)

                        Text(store.backend.modeDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var preview: UserProfile {
        UserProfile(id: "preview", username: cleanedUsername, displayName: displayName, emoji: emoji, colorHex: colorHex)
    }

    private func register() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            try await store.register(username: cleanedUsername,
                                     displayName: displayName.trimmingCharacters(in: .whitespaces),
                                     emoji: emoji,
                                     colorHex: colorHex)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ColorRow: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Theme.avatarColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selection == hex {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { selection = hex }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
