import UIKit

/// Resize + compress images for card attachments.
/// Default: 1280px max edge, JPEG quality 0.7 — sharp on Retina iPhones (~390pt × 3 = 1170px),
/// typical output 100–300 KB.
enum ImageCompressor {

    static func compress(_ image: UIImage,
                         maxEdge: CGFloat = 1280,
                         quality: CGFloat = 0.7) -> Data? {
        let resized = resize(image, maxEdge: maxEdge)
        return resized.jpegData(compressionQuality: quality)
    }

    static func compress(_ data: Data,
                         maxEdge: CGFloat = 1280,
                         quality: CGFloat = 0.7) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        return compress(img, maxEdge: maxEdge, quality: quality)
    }

    private static func resize(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard max(w, h) > maxEdge else { return image }

        let scale = maxEdge / max(w, h)
        let newSize = CGSize(width: w * scale, height: h * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // we already account for downscale; the resulting Data has correct pixel size
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
