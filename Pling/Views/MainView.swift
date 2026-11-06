import SwiftUI

/// Wie bei Snapchat: Links die Chats, in der Mitte die Kamera, rechts die Stories –
/// man wischt zwischen den Seiten hin und her.
struct MainView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $store.selectedTab) {
                ChatListView()
                    .tag(MainTab.chats)
                CameraScreen(target: .anyone, isActive: store.selectedTab == .camera)
                    .tag(MainTab.camera)
                StoriesView()
                    .tag(MainTab.stories)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            BottomBar(selected: $store.selectedTab, unread: store.unreadCount)
        }
        .ignoresSafeArea(.keyboard)
        .toast($store.toast)
        .fullScreenCover(item: $store.activeChat) { route in
            ChatView(conversationID: route.id)
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showProfile) {
            ProfileView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showAddFriend) {
            AddFriendView()
                .environmentObject(store)
        }
    }
}

struct BottomBar: View {
    @Binding var selected: MainTab
    let unread: Int

    private var onCamera: Bool { selected == .camera }

    var body: some View {
        HStack {
            tabButton(.chats, symbol: "bubble.left.and.bubble.right.fill", title: "Chats", badge: unread)
            Spacer()
            tabButton(.camera, symbol: "camera.fill", title: "Kamera", badge: 0)
            Spacer()
            tabButton(.stories, symbol: "person.2.fill", title: "Stories", badge: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background {
            if onCamera {
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                Rectangle().fill(.bar).ignoresSafeArea()
            }
        }
    }

    private func tabButton(_ tab: MainTab, symbol: String, title: String, badge: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { selected = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.brandPink, in: Capsule())
                                .offset(x: 12, y: -8)
                        }
                    }
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(width: 64)
            .foregroundStyle(color(for: tab))
        }
        .accessibilityLabel(title)
    }

    private func color(for tab: MainTab) -> Color {
        if onCamera { return tab == .camera ? .white : .white.opacity(0.75) }
        return tab == selected ? Theme.brand : .secondary
    }
}
