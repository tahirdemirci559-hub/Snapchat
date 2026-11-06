import PhotosUI
import SwiftUI

/// Wohin ein Snap gehen soll.
enum SnapTarget: Equatable {
    /// Von der Kamera-Seite: Empfänger werden danach ausgewählt.
    case anyone
    /// Aus einem Chat heraus: direkt an diesen Chat.
    case conversation(String)
}

struct EditableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CameraScreen: View {
    @EnvironmentObject private var store: AppStore
    let target: SnapTarget
    let isActive: Bool
    var onClose: (() -> Void)? = nil

    @StateObject private var camera = CameraModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var editing: EditableImage?
    @State private var shutterFlash = false

    private var isMainCamera: Bool { target == .anyone }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.status == .running {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .onTapGesture(count: 2) { camera.flip() }
            } else {
                unavailableView
            }

            Color.white
                .opacity(shutterFlash ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            controls
        }
        .onAppear { if isActive { camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: isActive) { _, active in
            if active { camera.start() } else { camera.stop() }
        }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            editing = EditableImage(image: image)
            camera.capturedImage = nil
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    editing = EditableImage(image: ImageTools.normalized(image))
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(item: $editing) { item in
            SnapEditorView(image: item.image, target: target) { sent in
                editing = nil
                if sent { onClose?() }
            }
            .environmentObject(store)
        }
    }

    // MARK: - Bedienelemente

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                if isMainCamera {
                    Button { store.showProfile = true } label: {
                        AvatarView(user: store.me, size: 38)
                    }
                    circleButton("person.badge.plus") { store.showAddFriend = true }
                } else {
                    circleButton("xmark") { onClose?() }
                }
                Spacer()
                VStack(spacing: 12) {
                    circleButton("arrow.triangle.2.circlepath.camera") { camera.flip() }
                    circleButton(camera.flashOn ? "bolt.fill" : "bolt.slash") { camera.flashOn.toggle() }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            HStack(alignment: .center) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .accessibilityLabel("Foto auswählen")

                Spacer()

                Button(action: shoot) {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 6)
                            .frame(width: 84, height: 84)
                        Circle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 68, height: 68)
                    }
                }
                .accessibilityLabel("Foto aufnehmen")

                Spacer()

                Button(action: useDemoImage) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .accessibilityLabel("Lustigen Test-Snap erstellen")
            }
            .padding(.horizontal, 36)
            .padding(.bottom, isMainCamera ? 96 : 30)
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.3), in: Circle())
        }
    }

    private var unavailableView: some View {
        ZStack {
            Theme.gradient.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: camera.status == .denied ? "video.slash.fill" : "camera.fill")
                    .font(.system(size: 48))
                switch camera.status {
                case .denied:
                    Text("Kein Zugriff auf die Kamera")
                        .font(.headline)
                    Text("Erlaube den Zugriff in den Einstellungen.")
                        .font(.subheadline)
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.3))
                case .unavailable:
                    Text("Keine Kamera verfügbar")
                        .font(.headline)
                    Text("Wähle ein Foto aus oder tippe auf 🙂 für einen Test-Snap.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                default:
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(40)
        }
    }

    // MARK: - Aktionen

    private func shoot() {
        guard camera.status == .running else {
            useDemoImage()
            return
        }
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.25).delay(0.08)) { shutterFlash = false }
        camera.capture()
    }

    private func useDemoImage() {
        let options: [(String, String)] = [("🎉", "Party!"), ("😎", "Chillen"), ("🍕", "Pizza-Zeit"),
                                           ("🌞", "Guten Morgen!"), ("🐱", "Miau"), ("⚽️", "Tor!!!")]
        let pick = options.randomElement() ?? ("🎉", "Hallo!")
        let palettes: [[UIColor]] = [[.systemPurple, .systemPink], [.systemOrange, .systemRed],
                                     [.systemTeal, .systemBlue], [.systemGreen, .systemMint]]
        let image = ImageTools.demoImage(emoji: pick.0, text: pick.1,
                                         colors: palettes.randomElement() ?? [.systemPurple, .systemPink])
        editing = EditableImage(image: image)
    }
}
