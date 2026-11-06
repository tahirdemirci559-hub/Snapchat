import SwiftUI

/// Zeigt einen empfangenen Snap im Vollbild – mit Countdown. Danach ist er weg.
struct SnapViewer: View {
    let message: Message
    let senderName: String
    let onClose: () -> Void

    @State private var remaining: Double = 0
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var total: Double { Double(message.snapDuration ?? 0) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = UIImage(data: message.imageData ?? Data()) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                Text("Snap nicht mehr verfügbar")
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(senderName).font(.headline)
                        Text(message.sentAt.shortAgo).font(.caption)
                    }
                    Spacer()
                    if total > 0 {
                        ZStack {
                            Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: remaining / total)
                                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(remaining.rounded(.up)))")
                                .font(.caption.bold())
                        }
                        .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "infinity")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .shadow(radius: 4)
                .padding()
                Spacer()
                Text("Tippen zum Schließen")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .statusBarHidden()
        .onAppear { remaining = total }
        .onReceive(tick) { _ in
            guard total > 0 else { return }
            remaining = max(0, remaining - 0.05)
            if remaining <= 0 { onClose() }
        }
    }
}
