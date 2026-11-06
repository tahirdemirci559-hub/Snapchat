import SwiftUI

struct StoryViewerRoute: Identifiable {
    let id = UUID()
    let groups: [AppStore.StoryGroup]
    let startIndex: Int
}

/// Rechte Seite: eigene Story und die Stories der Freunde zum Durchscrollen.
struct StoriesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var viewer: StoryViewerRoute?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let friendGroups = store.storyGroups(includeMine: false)
        let unseen = friendGroups.filter { store.hasUnviewedStories($0) }
        let seen = friendGroups.filter { !store.hasUnviewedStories($0) }
        let ordered = unseen + seen

        VStack(spacing: 0) {
            PageHeader(title: "Stories") {
                Color.clear.frame(width: 38, height: 38)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    myStoryCard

                    if !friendGroups.isEmpty {
                        // Kreise oben zum schnellen Antippen
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, group in
                                    Button {
                                        viewer = StoryViewerRoute(groups: ordered, startIndex: index)
                                    } label: {
                                        VStack(spacing: 4) {
                                            AvatarView(user: group.author, size: 60, ring: store.hasUnviewedStories(group))
                                            Text(group.author.displayName)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .frame(width: 70)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if friendGroups.isEmpty {
                        VStack(spacing: 10) {
                            Text("📭").font(.system(size: 56))
                            Text("Noch keine Stories").font(.headline)
                            Text("Wenn deine Freunde etwas posten, siehst du es hier.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        Text("Freunde")
                            .font(.title3.bold())
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, group in
                                Button {
                                    viewer = StoryViewerRoute(groups: ordered, startIndex: index)
                                } label: {
                                    StoryCard(group: group, unseen: store.hasUnviewedStories(group))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.top, 4)
            }
        }
        .background(Color(.systemBackground))
        .fullScreenCover(item: $viewer) { route in
            StoryViewer(groups: route.groups, startIndex: route.startIndex)
                .environmentObject(store)
        }
    }

    private var myStoryCard: some View {
        let mine = store.myStories
        return HStack(spacing: 14) {
            Button {
                if !mine.isEmpty, let me = store.me {
                    viewer = StoryViewerRoute(groups: [AppStore.StoryGroup(author: me, stories: mine)], startIndex: 0)
                } else {
                    store.selectedTab = .camera
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(user: store.me, size: 60, ring: !mine.isEmpty)
                    if mine.isEmpty {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Theme.brand)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("Meine Story").font(.headline)
                if mine.isEmpty {
                    Text("Tippe, um etwas zu posten").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let views = Set(mine.flatMap(\.viewedBy)).count
                    Text("\(mine.count) Snap\(mine.count == 1 ? "" : "s") · 👁 \(views) angesehen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.selectedTab = .camera
            } label: {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.gradient, in: Circle())
            }
            .accessibilityLabel("Story aufnehmen")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }
}

struct StoryCard: View {
    let group: AppStore.StoryGroup
    let unseen: Bool

    var body: some View {
        let story = group.stories.last
        ZStack(alignment: .bottomLeading) {
            Group {
                if let story, let image = ImageCache.shared.image(id: story.id, data: story.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(hex: group.author.colorHex)
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            HStack(spacing: 8) {
                AvatarView(user: group.author, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.author.displayName)
                        .font(.subheadline.bold())
                    Text(group.latest.shortAgo)
                        .font(.caption2)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(unseen ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear), lineWidth: 3)
        }
    }
}
