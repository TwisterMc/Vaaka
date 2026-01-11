import AppKit
import CoreImage

final class FaviconColorExtractor {
    static let shared = FaviconColorExtractor()
    private init() {}

    private let cache = NSCache<NSString, NSColor>()
    private let ciContext = CIContext(options: nil)

    func cachedColor(forSiteID id: String) -> NSColor? {
        return cache.object(forKey: id as NSString)
    }

    func invalidate(forSiteID id: String) {
        cache.removeObject(forKey: id as NSString)
    }

    func computeAndCacheColor(for site: Site) -> NSColor? {
        // Prefer explicit favicon image
        var image: NSImage?
        if let name = site.favicon {
            image = FaviconFetcher.shared.image(forResource: name)
        }
        // Fallback to generated mono icon
        if image == nil, let host = site.url.host {
            image = FaviconFetcher.shared.generateMonoIcon(for: host)
        }
        guard let img = image else { return nil }
        guard let color = dominantColor(from: img) else { return nil }
        cache.setObject(color, forKey: site.id as NSString)
        return color
    }

    // Compute dominant/average color using Core Image (CIAreaAverage)
    private func dominantColor(from image: NSImage) -> NSColor? {
        guard let data = image.tiffRepresentation, let ciImage = CIImage(data: data) else { return nil }
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height), forKey: kCIInputExtentKey)
        guard let outputImage = filter?.outputImage else { return nil }

        // Render to 1x1 pixel and read RGBA
        var bitmap = [UInt8](repeating: 0, count: 4)
        let outputExtent = CGRect(x: 0, y: 0, width: 1, height: 1)
        ciContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: outputExtent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0
        var a = CGFloat(bitmap[3]) / 255.0
        // Ensure sufficient opacity
        if a < 0.6 { a = 0.6 }

        // Boost saturation slightly to make the color more vivid
        let color = NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
        return color.usingColorSpace(.deviceRGB)
    }
}
