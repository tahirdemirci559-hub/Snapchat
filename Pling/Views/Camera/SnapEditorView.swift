import SwiftUI
import UIKit

/// Ein gezeichneter Strich. Punkte sind relativ zur Bildgröße (0…1), damit sie
/// beim Speichern in voller Auflösung an der richtigen Stelle landen.
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    /// Strichbreite relativ zur Bildbreite.
    var width: CGFloat
}

struct SnapEditorView: View {
    @EnvironmentObject private var store: AppStore
    let original: UIImage
    let target: SnapTarget
    /// `true`, wenn gesendet wurde.
    let onFinish: (Bool) -> Void

    @State private var filter: SnapFilter = .original
    @State private var filtered: UIImage
    @State private var caption = ""
    @State private var captionY: CGFloat = 0.62
    @State private var showCaption = false
    @State private var isDrawing = false
    @State private var strokes: [Stroke] = []
    @State private var penColor: Color = .white
    @State private var duration: Int? = 5
    @State private var showSendSheet = false
    @State private var isSending = false
    @State private var renderedForSend: UIImage?
    @FocusState private var captionFocused: Bool

    private let penColors: [Color] = [.white, .black, Color(hex: "FF5CAA"), Color(hex: "7B5CFF"),
                                      Color(hex: "1FB8C8"), Color(hex: "38C98B"), Color(hex: "FFB938"), Color(hex: "F25555")]
    private let durations: [Int?] = [3, 5, 10, nil]

    init(image: UIImage, target: SnapTarget, onFinish: @escaping (Bool) -> Void) {
        self.original = image
        self.target = target
        self.onFinish = onFinish
        _filtered = State(initialValue: image)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let frame = fittedSize(for: original.size, in: geo.size)
                canvas(size: frame)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .ignoresSafeArea(.keyboard)

            VStack {
                topBar
                Spacer()
                if isDrawing { penPalette }
                filterBar
                bottomBar
            }
        }
        .statusBarHidden()
        .toast($store.toast)
        .onChange(of: filter) { _, newFilter in
            filtered = ImageTools.apply(newFilter, to: original)
        }
        .sheet(isPresented: $showSendSheet) {
            if let image = renderedForSend {
                SendToView(image: image, duration: duration) { sent in
                    showSendSheet = false
                    if sent { onFinish(true) }
                }
                .environmentObject(store)
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Bildfläche

    private func canvas(size: CGSize) -> some View {
        ZStack {
            Image(uiImage: filtered)
                .resizable()
                .scaledToFill()

            Canvas { context, canvasSize in
                for stroke in strokes {
                    var path = Path()
                    guard let first = stroke.points.first else { continue }
                    path.move(to: CGPoint(x: first.x * canvasSize.width, y: first.y * canvasSize.height))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * canvasSize.width, y: point.y * canvasSize.height))
                    }
                    context.stroke(path, with: .color(stroke.color),
                                   style: StrokeStyle(lineWidth: stroke.width * canvasSize.width, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(isDrawing)
            .gesture(drawGesture(size: size), including: isDrawing ? .all : .none)

            if showCaption || !caption.isEmpty {
                captionBar(size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDrawing else { return }
            if captionFocused {
                captionFocused = false
            } else {
                startCaption()
            }
        }
    }

    private func captionBar(size: CGSize) -> some View {
        let fontSize = size.width * 0.05
        return TextField("", text: $caption, axis: .vertical)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1...3)
            .focused($captionFocused)
            .submitLabel(.done)
            .padding(.vertical, fontSize * 0.45)
            .padding(.horizontal, fontSize * 0.5)
            .frame(width: size.width)
            .background(.black.opacity(0.55))
            .position(x: size.width / 2, y: captionY * size.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        captionY = min(max(value.location.y / size.height, 0.06), 0.94)
                    }
            )
            .onChange(of: captionFocused) { _, focused in
                if !focused && caption.trimmingCharacters(in: .whitespaces).isEmpty {
                    caption = ""
                    showCaption = false
                }
            }
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                if value.translation == .zero || strokes.isEmpty || value.startLocation == value.location {
                    strokes.append(Stroke(points: [point], color: penColor, width: 6 / size.width))
                } else {
                    strokes[strokes.count - 1].points.append(point)
                }
            }
    }

    // MARK: - Werkzeuge

    private var topBar: some View {
        HStack(alignment: .top) {
            toolButton("xmark") { onFinish(false) }
            Spacer()
            VStack(spacing: 14) {
                toolButton("textformat", active: showCaption) {
                    isDrawing = false
                    startCaption()
                }
                toolButton("pencil.tip", active: isDrawing) {
                    captionFocused = false
                    isDrawing.toggle()
                }
                if !strokes.isEmpty {
                    toolButton("arrow.uturn.backward") { strokes.removeLast() }
                }
                Menu {
                    ForEach(durations, id: \.self) { value in
                        Button {
                            duration = value
                        } label: {
                            if duration == value {
                                Label(durationLabel(value), systemImage: "checkmark")
                            } else {
                                Text(durationLabel(value))
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 18, weight: .semibold))
                        Text(duration.map { "\($0)s" } ?? "∞")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 50)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Anzeigedauer")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var penPalette: some View {
        HStack(spacing: 10) {
            ForEach(penColors, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(.white, lineWidth: penColor == color ? 3 : 1))
                    .onTapGesture { penColor = color }
            }
        }
        .padding(10)
        .background(.black.opacity(0.35), in: Capsule())
        .padding(.bottom, 6)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SnapFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.footnote.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(filter == item ? .black : .white)
                            .background(filter == item ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.35)),
                                        in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                UIImageWriteToSavedPhotosAlbum(renderFinalImage(), nil, nil, nil)
                store.toast = "In Fotos gespeichert 📥"
            } label: {
                Label("Speichern", systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.35), in: Capsule())
            }

            Spacer()

            Button(action: send) {
                HStack(spacing: 8) {
                    if isSending { ProgressView().tint(.white) }
                    Text(sendTitle)
                        .font(.headline)
                    Image(systemName: "paperplane.fill")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.gradient, in: Capsule())
            }
            .disabled(isSending)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func startCaption() {
        showCaption = true
        // Kurz warten, bis das Textfeld existiert, dann Tastatur öffnen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { captionFocused = true }
    }

    private var sendTitle: String {
        if case .conversation = target { return "Senden" }
        return "Senden an"
    }

    private func toolButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? .black : .white)
                .frame(width: 44, height: 44)
                .background(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
        }
    }

    private func durationLabel(_ value: Int?) -> String {
        guard let value else { return "Unbegrenzt" }
        return "\(value) Sekunden"
    }

    // MARK: - Senden

    private func send() {
        captionFocused = false
        isDrawing = false
        let image = renderFinalImage()
        switch target {
        case .anyone:
            renderedForSend = image
            showSendSheet = true
        case .conversation(let id):
            isSending = true
            Task {
                let ok = await store.sendSnap(image, duration: duration, toFriends: [],
                                              toConversations: [id], toStory: false)
                isSending = false
                if ok { onFinish(true) }
            }
        }
    }

    /// Zeichnet Bild, Striche und Text in voller Auflösung zusammen.
    private func renderFinalImage() -> UIImage {
        let base = filtered
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                cg.setStrokeColor(UIColor(stroke.color).cgColor)
                cg.setLineWidth(stroke.width * size.width)
                cg.beginPath()
                cg.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                if stroke.points.count == 1 {
                    cg.addLine(to: CGPoint(x: first.x * size.width + 0.1, y: first.y * size.height))
                }
                for point in stroke.points.dropFirst() {
                    cg.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                cg.strokePath()
            }

            guard !text.isEmpty else { return }
            let fontSize = size.width * 0.05
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para
            ]
            let maxWidth = size.width - fontSize
            let textSize = (text as NSString).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                           options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).size
            let barHeight = textSize.height + fontSize * 0.9
            let bar = CGRect(x: 0, y: captionY * size.height - barHeight / 2, width: size.width, height: barHeight)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            cg.fill(bar)
            (text as NSString).draw(in: CGRect(x: fontSize / 2, y: bar.minY + fontSize * 0.45,
                                               width: maxWidth, height: textSize.height + 2),
                                    withAttributes: attrs)
        }
    }

    private func fittedSize(for image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let scale = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
