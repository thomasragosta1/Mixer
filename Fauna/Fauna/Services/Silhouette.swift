import CoreImage
import UIKit
import Vision

/// Cuts the animal out of its photo (the same "lift subject" iOS uses in Photos) and returns
/// a solid silhouette, cropped tight, for drawing to scale. Nil when Vision can't find a
/// subject (or isn't available, as in the simulator); callers fall back to a symbol.
enum Silhouette {
    @MainActor private static var cache: [String: UIImage] = [:]
    @MainActor private static var failed: Set<String> = []

    @MainActor
    static func make(for animal: Animal) async -> UIImage? {
        if let hit = cache[animal.id] { return hit }
        if failed.contains(animal.id) { return nil }
        guard let photo = await WikiImages.shared.image(for: animal.wikipediaTitle, size: .card),
              let cg = photo.cgImage else { return nil }
        let result = await Task.detached(priority: .userInitiated) { cutOut(cg) }.value
        if let result { cache[animal.id] = result } else { failed.insert(animal.id) }
        return result
    }

    private static func cutOut(_ image: CGImage) -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              // The largest subject, not every one: a photo of a bird on a branch keeps the bird.
              let instance = largestInstance(observation, handler: handler),
              let buffer = try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler)
        else { return nil }

        let mask = CIImage(cvPixelBuffer: buffer)
        let w = Int(mask.extent.width), h = Int(mask.extent.height)
        guard w > 8, h > 8 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(mask, toBitmap: &pixels, rowBytes: w, bounds: mask.extent, format: .L8, colorSpace: nil)

        // Tight bounding box of the subject (row 0 is the top of the image).
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[y * w + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX + 8, maxY > minY + 8 else { return nil }
        // A "subject" that fills almost the whole frame is usually the background, not an animal.
        let area = Double((maxX - minX) * (maxY - minY)) / Double(w * h)
        guard area < 0.97 else { return nil }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let gray = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: gray)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)
        guard let solid = ctx.makeImage(),
              let cropped = solid.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return nil }
        return UIImage(cgImage: cropped).withRenderingMode(.alwaysTemplate)
    }

    private static func largestInstance(_ observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) -> Int? {
        let instances = Array(observation.allInstances)
        guard instances.count > 1 else { return instances.first }
        var best: (Int, Int)?
        for i in instances {
            guard let buf = try? observation.generateMask(forInstances: [i]) else { continue }
            CVPixelBufferLockBaseAddress(buf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buf) else { continue }
            let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
            let row = CVPixelBufferGetBytesPerRow(buf)
            var count = 0
            for y in 0..<h {
                let p = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
                for x in 0..<w where p[x] > 0.5 { count += 1 }
            }
            if count > (best?.1 ?? -1) { best = (i, count) }
        }
        return best?.0
    }
}
