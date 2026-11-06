import SwiftUI

@MainActor
final class MessagesModel: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var loaded = false
    private var token: ListenerToken?

    func start(backend: ChatBackend, conversationID: String) {
        guard token == nil else { return }
        token = backend.observeMessages(conversationID: conversationID) { [weak self] list in
            self?.messages = list
            self?.loaded = true
        }
    }

    func stop() {
        token?.cancel()
        token = nil
    }
}

struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let conversationID: String

    @StateObject private var model = MessagesModel()
    @State private var draft = ""
    @State private var showCamera = false
    @State private var viewingSnap: Message?
    @FocusState private var inputFocused: Bool

    private var conversation: Conversation? { store.conversation(id: conversationID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            inputBar
        }
        .background(Color(.systemBackground))
        .toast($store.toast)
        .onAppear { model.start(backend: store.backend, conversationID: conversationID) }
        .onDisappear { model.stop() }
        .onChange(of: model.messages) { _, _ in markReadIfPossible() }
        .onChange(of: conversation?.lastActivity) { _, _ in markReadIfPossible() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraScreen(target: .conversation(conversationID), isActive: true) {
                showCamera = false
            }
            .environmentObject(store)
        }
        .fullScreenCover(item: $viewingSnap) { snap in
            SnapViewer(message: snap, senderName: store.user(snap.senderID)?.displayName ?? "Snap") {
                viewingSnap = nil
            }
        }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Schließen")

            if let conversation {
                AvatarView(user: store.avatarUser(for: conversation), size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.title(for: conversation))
                        .font(.headline)
                        .lineLimit(1)
                    if conversation.isGroup {
                        Text("\(conversation.participantIDs.count) Mitglieder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let other = store.otherParticipants(in: conversation).first {
                        Text("@\(other.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StreakBadge(count: conversation.activeStreak)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Nachrichten

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if model.loaded && model.messages.isEmpty {
                        VStack(spacing: 8) {
                            Text("👋").font(.system(size: 48))
                            Text("Sag Hallo!")
                                .font(.headline)
                            Text("Schreib eine Nachricht oder schick einen Snap.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? model.messages[index - 1] : nil
                        if previous == nil || !Calendar.current.isDate(previous!.sentAt, inSameDayAs: message.sentAt) {
                            DayDivider(date: message.sentAt)
                        }
                        MessageRow(message: message,
                                   isMine: message.senderID == store.me?.id,
                                   showSender: (conversation?.isGroup ?? false) && previous?.senderID != message.senderID,
                                   sender: store.user(message.senderID),
                                   myID: store.me?.id ?? "",
                                   onOpenSnap: { open(message) },
                                   onDelete: { Task { await store.delete(message) } })
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newID, anchor: .bottom) }
            }
            .onAppear {
                if let last = model.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: model.loaded) { _, _ in
                if let last = model.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    // MARK: - Eingabe

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                inputFocused = false
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.gradient, in: Circle())
            }
            .accessibilityLabel("Snap aufnehmen")

            TextField("Nachricht senden", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.chat, in: Circle())
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.spring(duration: 0.25), value: draft.isEmpty)
        .background(.bar)
    }

    // MARK: - Aktionen

    private func send() {
        guard let conversation else { return }
        let text = draft
        draft = ""
        Task { await store.sendText(text, in: conversation) }
    }

    private func open(_ message: Message) {
        guard let me = store.me, message.senderID != me.id,
              message.imageData != nil, !message.viewedBy.contains(me.id) else { return }
        inputFocused = false
        viewingSnap = message
        if let conversation {
            Task { await store.markSnapViewed(message, in: conversation) }
        }
    }

    /// Als gelesen markieren – aber nur, wenn keine ungeöffneten Snaps mehr warten.
    private func markReadIfPossible() {
        guard let conversation, let me = store.me, model.loaded else { return }
        let waitingSnap = model.messages.contains {
            $0.kind == .snap && $0.senderID != me.id && $0.imageData != nil && !$0.viewedBy.contains(me.id)
        }
        if !waitingSnap {
            Task { await store.markRead(conversation) }
        }
    }
}

struct DayDivider: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }

    private var label: String {
        if Calendar.current.isDateInToday(date) { return "Heute" }
        if Calendar.current.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct MessageRow: View {
    let message: Message
    let isMine: Bool
    let showSender: Bool
    let sender: UserProfile?
    let myID: String
    let onOpenSnap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            if showSender && !isMine {
                Text(sender?.displayName ?? "Unbekannt")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: sender?.colorHex ?? "888888"))
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
            }
            HStack {
                if isMine { Spacer(minLength: 50) }
                content
                if !isMine { Spacer(minLength: 50) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            VStack(alignment: .trailing, spacing: 2) {
                Text(message.text ?? "")
                    .font(.body)
                    .foregroundStyle(isMine ? .white : .primary)
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(isMine ? .white.opacity(0.75) : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isMine ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                if isMine {
                    Button(role: .destructive, action: onDelete) {
                        Label("Für alle löschen", systemImage: "trash")
                    }
                }
            }

        case .snap:
            Button(action: onOpenSnap) {
                HStack(spacing: 10) {
                    Image(systemName: snapSymbol)
                        .font(.system(size: 20, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapTitle).font(.subheadline.bold())
                        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(snapIsWaiting ? .white : Theme.snap)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(snapIsWaiting ? AnyShapeStyle(Theme.snap) : AnyShapeStyle(Theme.snap.opacity(0.12)))
                }
            }
            .buttonStyle(.plain)
            .disabled(!snapIsWaiting)
        }
    }

    private var snapIsWaiting: Bool {
        !isMine && message.imageData != nil && !message.viewedBy.contains(myID)
    }

    private var snapTitle: String {
        if isMine {
            return message.viewedBy.isEmpty ? "Snap gesendet" : "Snap geöffnet"
        }
        return snapIsWaiting ? "Tippen zum Ansehen" : "Snap angesehen"
    }

    private var snapSymbol: String {
        if isMine { return message.viewedBy.isEmpty ? "paperplane.fill" : "paperplane" }
        return snapIsWaiting ? "square.fill" : "square"
    }
}
