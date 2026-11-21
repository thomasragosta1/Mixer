import UIKit

/// Finds the lead photo of a Wikipedia article and loads it, with memory and disk caching.
///
/// Photos come from Wikimedia Commons through the Wikipedia REST summary API. Resolved URLs are
/// remembered in UserDefaults, so after the first look an animal's photo loads straight from cache.
actor WikiImages {
    static let shared = WikiImages()

    /// Wikimedia serves thumbnails at a set of standard widths.
    enum Size: Int { case card = 500, hero = 1280 }

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var resolved: [String: URL]
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private static let defaultsKey = "WikiImages.resolved.v1"

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "Fauna/1.0 (iOS; daily animal reader)"]
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        memory.countLimit = 80
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        resolved = saved.compactMapValues(URL.init(string:))
    }

    func image(for title: String, size: Size) async -> UIImage? {
        let key = "\(title)#\(size.rawValue)"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = inflight[key] { return await running.value }
        let task = Task<UIImage?, Never> { [session] in
            guard let url = await self.imageURL(for: title, size: size) else { return nil }
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Warms the cache for animals the reader is about to see.
    func prefetch(_ titles: [String], size: Size) {
        for title in titles {
            Task { _ = await image(for: title, size: size) }
        }
    }

    private func imageURL(for title: String, size: Size) async -> URL? {
        let key = "\(title)#\(size.rawValue)"
        if let url = resolved[key] { return url }
        let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: Self.pathSafe) ?? title
        guard let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)"),
              let (data, _) = try? await session.data(from: api),
              let summary = try? JSONDecoder().decode(Summary.self, from: data) else { return nil }
        guard let url = Self.pick(summary, width: size.rawValue) else { return nil }
        resolved[key] = url
        UserDefaults.standard.set(resolved.mapValues(\.absoluteString), forKey: Self.defaultsKey)
        return url
    }

    private static let pathSafe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.()'")

    /// Uses the original when it's already small; otherwise asks Wikimedia for a standard-width thumbnail.
    private static func pick(_ s: Summary, width: Int) -> URL? {
        if let original = s.originalimage, original.width <= width {
            return URL(string: original.source)
        }
        guard let thumb = s.thumbnail?.source, var components = URLComponents(string: thumb) else {
            return s.originalimage.flatMap { URL(string: $0.source) }
        }
        var parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let last = parts.last, let px = last.range(of: "px-"), last[..<px.lowerBound].allSatisfy(\.isNumber) {
            parts[parts.count - 1] = "\(width)" + last[px.lowerBound...]
            components.percentEncodedPath = parts.joined(separator: "/")
        }
        return components.url
    }

    private struct Summary: Decodable {
        struct Image: Decodable { let source: String; let width: Int; let height: Int }
        let thumbnail: Image?
        let originalimage: Image?
    }
}
