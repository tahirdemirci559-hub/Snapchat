import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum SnapFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case vivid = "Lebhaft"
    case warm = "Warm"
    case cool = "Kühl"
    case mono = "S/W"
    case noir = "Noir"
    case retro = "Retro"

    var id: String { rawValue }
}

enum ImageTools {
    private static let context = CIContext()

    /// Dreht das Bild richtig herum und verkleinert es auf `maxDimension`.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 1440) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func apply(_ filter: SnapFilter, to image: UIImage) -> UIImage {
        guard filter != .original, let input = CIImage(image: image) else { return image }

        let output: CIImage?
        switch filter {
        case .original:
            output = input
        case .vivid:
            let f = CIFilter.colorControls()
            f.inputImage = input
            f.saturation = 1.6
            f.contrast = 1.08
            output = f.outputImage
        case .warm:
            let f = CIFilter.colorMatrix()
            f.inputImage = input
            f.rVector = CIVector(x: 1.12, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 1.02, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: 0.85, w: 0)
            output = f.outputImage
        case .cool:
            let f = CIFilter.colorMatrix()
            f.inputImage = input
            f.rVector = CIVector(x: 0.88, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: 1.15, w: 0)
            output = f.outputImage
        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = input
            output = f.outputImage
        case .noir:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = input
            output = f.outputImage
        case .retro:
            let f = CIFilter.photoEffectInstant()
            f.inputImage = input
            output = f.outputImage
        }

        guard let output, let cg = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg)
    }

    /// Komprimiert ein Bild so, dass es klein genug für den Versand ist (< 1 MB).
    static func jpegData(_ image: UIImage, maxDimension: CGFloat = 1280, quality: CGFloat = 0.6) -> Data? {
        normalized(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    /// Erzeugt ein buntes Bild (für Demo-Stories oder den Simulator ohne Kamera).
    static func demoImage(emoji: String, text: String, colors: [UIColor]) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cgColors = colors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: size.width, y: size.height),
                                                 options: [])
            }
            let para = NSMutableParagraphStyle()
            para.alignment = .center

            let emojiAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 380),
                .paragraphStyle: para
            ]
            (emoji as NSString).draw(in: CGRect(x: 0, y: 520, width: size.width, height: 480), withAttributes: emojiAttrs)

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 84, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para
            ]
            (text as NSString).draw(in: CGRect(x: 60, y: 1080, width: size.width - 120, height: 400), withAttributes: textAttrs)
        }
    }
}

/// Kleiner Zwischenspeicher, damit Bilder nicht bei jedem Neuzeichnen neu dekodiert werden.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(id: String, data: Data?) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }
}
