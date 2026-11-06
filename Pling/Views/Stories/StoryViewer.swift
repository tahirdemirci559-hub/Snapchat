import SwiftUI

/// Vollbild-Story: tippen rechts = weiter, links = zurück, nach unten wischen = schließen.
struct StoryViewer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let groups: [AppStore.StoryGroup]
    @State private var groupIndex: Int
    @State private var storyIndex = 0
    @State private var progress: Double = 0
    @State private var dragOffset: CGFloat = 0
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    private let storyDuration: Double = 5
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(groups: [AppStore.StoryGroup], startIndex: Int) {
        self.groups = groups
        _groupIndex = State(initialValue: min(max(startIndex, 0), max(groups.count - 1, 0)))
    }

    private var group: AppStore.StoryGroup? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }
    private var story: Story? {
        guard let group, group.stories.indices.contains(storyIndex) else { return nil }
        return group.stories[storyIndex]
    }
    private var isMine: Bool { group?.author.id == store.me?.id }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story, let image = ImageCache.shared.image(id: story.id, data: story.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Tipp-Zonen
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { previous() }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                progressBars
                header
                Spacer()
                footer
            }
            .padding(.horizontal, 10)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() } else {
                        withAnimation(.spring) { dragOffset = 0 }
                    }
                }
        )
        .statusBarHidden()
        .toast($store.toast)
        .onAppear(perform: markViewed)
        .onReceive(tick) { _ in
            guard !replyFocused, story != nil else { return }
            progress += 0.05 / storyDuration
            if progress >= 1 { next() }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array((group?.stories ?? []).enumerated()), id: \.element.id) { index, _ in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: geo.size.width * fill(for: index))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.top, 8)
    }

    private func fill(for index: Int) -> CGFloat {
        if index < storyIndex { return 1 }
        if index == storyIndex { return min(progress, 1) }
        return 0
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarView(user: group?.author, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(isMine ? "Meine Story" : (group?.author.displayName ?? ""))
                    .font(.subheadline.bold())
                if let story {
                    Text(story.postedAt.shortAgo).font(.caption)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
        }
        .foregroundStyle(.white)
        .shadow(radius: 3)
    }

    @ViewBuilder
    private var footer: some View {
        if isMine, let story {
            HStack {
                Label("\(story.viewedBy.count) angesehen", systemImage: "eye.fill")
                    .font(.subheadline.bold())
                Spacer()
                Button(role: .destructive) {
                    Task {
                        await store.deleteStory(story)
                        dismiss()
                    }
                } label: {
                    Label("Löschen", systemImage: "trash")
                        .font(.subheadline.bold())
                }
            }
            .foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.bottom, 10)
        } else if let author = group?.author {
            HStack(spacing: 8) {
                TextField("Antworten an \(author.displayName) …", text: $reply)
                    .focused($replyFocused)
                    .submitLabel(.send)
                    .onSubmit { sendReply(to: author) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.2), in: Capsule())
                    .foregroundStyle(.white)
                if !reply.isEmpty {
                    Button { sendReply(to: author) } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.gradient, in: Circle())
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - Navigation

    private func next() {
        guard let group else { dismiss(); return }
        if storyIndex + 1 < group.stories.count {
            storyIndex += 1
        } else if groupIndex + 1 < groups.count {
            groupIndex += 1
            storyIndex = 0
        } else {
            dismiss()
            return
        }
        progress = 0
        markViewed()
    }

    private func previous() {
        if storyIndex > 0 {
            storyIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            storyIndex = max(groups[groupIndex].stories.count - 1, 0)
        }
        progress = 0
    }

    private func markViewed() {
        guard let story else { return }
        Task { await store.markStoryViewed(story) }
    }

    private func sendReply(to author: UserProfile) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let me = store.me else { return }
        reply = ""
        replyFocused = false
        Task {
            do {
                let conversation = try await store.backend.openConversation(participants: [me.id, author.id], title: nil)
                await store.sendText("Antwort auf deine Story: \(text)", in: conversation)
                store.toast = "Antwort gesendet 💬"
            } catch {
                store.showError(error)
            }
        }
    }
}
