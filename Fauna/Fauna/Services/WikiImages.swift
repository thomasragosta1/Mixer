import UIKit

/// Who took a photo and under what license, as recorded on Wikimedia Commons.
struct PhotoCredit: Codable, Hashable {
    /// Commons file name, e.g. "Red_Panda_(24986761703).jpg".
    let file: String
    let author: String
    let license: String
    let licenseURL: URL?
    /// The file's page on Commons, which carries the full attribution.
    let pageURL: URL

    /// "Photo: Jane Smith, CC BY-SA 4.0"
    var line: String {
        let who = author.isEmpty ? "Wikimedia Commons" : author
        return license.isEmpty ? "Photo: \(who)" : "Photo: \(who), \(license)"
    }
}

/// Finds the lead photo of a Wikipedia article, checks that it is a freely licensed file on
/// Wikimedia Commons (not a 'fair use' upload, which can't be reused), records its author and
/// license, and loads it at a standard width with memory and disk caching.
actor WikiImages {
    static let shared = WikiImages()

    /// Wikimedia serves thumbnails at a set of standard widths.
    enum Size: Int { case card = 500, hero = 1280, full = 1920 }

    /// Everything needed to load and credit one article's photo.
    private struct Source: Codable {
        let original: URL
        let width: Int
        let credit: PhotoCredit
    }

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var sources: [String: Source]
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var resolving: [String: Task<Source?, Never>] = [:]
    /// Wikipedia rate-limits bursts, so at most a few lookups run at once.
    private var activeLookups = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let maxLookups = 3
    private static let defaultsKey = "WikiImages.sources.v2"

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "Fauna/1.0 (iOS; daily animal reader)"]
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        memory.countLimit = 80
        // Photo files and credits are resolved at build time (scripts/fetch_photos.py) and
        // bundled, so the app doesn't need to look them up. Runtime lookup is the fallback.
        var known: [String: Source] = [:]
        if let url = Bundle.main.url(forResource: "photos", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? JSONDecoder().decode([String: Source].self, from: data) {
            known = bundled
        }
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Source].self, from: data) {
            known.merge(saved) { bundled, _ in bundled }
        }
        sources = known
    }

    // MARK: Public

    func image(for title: String, size: Size) async -> UIImage? {
        let key = "\(title)#\(size.rawValue)"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = inflight[key] { return await running.value }
        let task = Task<UIImage?, Never> { [session] in
            guard let source = await self.source(for: title) else { return nil }
            let url = Self.url(for: source, width: size.rawValue)
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

    /// Author and license for the article's photo, or nil if it has no reusable photo.
    func credit(for title: String) async -> PhotoCredit? {
        await source(for: title)?.credit
    }

    /// Warms the cache for animals the reader is about to see.
    func prefetch(_ titles: [String], size: Size) {
        for title in titles {
            Task { _ = await image(for: title, size: size) }
        }
    }

    // MARK: Resolving

    private func source(for title: String) async -> Source? {
        if let known = sources[title] { return known }
        if let running = resolving[title] { return await running.value }
        let task = Task<Source?, Never> { await self.resolve(title) }
        resolving[title] = task
        let source = await task.value
        resolving[title] = nil
        if let source {
            sources[title] = source
            if let data = try? JSONEncoder().encode(sources) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
        }
        return source
    }

    private func resolve(_ title: String) async -> Source? {
        await acquireLookup()
        defer { releaseLookup() }
        let path = Self.pathComponent(title)

        // 1. The article's lead image.
        var file: String?
        if let summary: Summary = await fetch("https://en.wikipedia.org/api/rest_v1/page/summary/\(path)"),
           let lead = summary.originalimage?.source, lead.contains("/wikipedia/commons/") {
            file = Self.fileName(fromUploadURL: lead)
        }
        // 2. A lead image hosted on English Wikipedia itself is usually 'fair use' and can't be
        //    reused, so take the first Commons photo in the article instead.
        if file == nil, let media: MediaList = await fetch("https://en.wikipedia.org/api/rest_v1/page/media-list/\(path)") {
            file = media.items.first { item in
                item.type == "image" && (item.srcset?.contains { $0.src.contains("/wikipedia/commons/") } ?? false)
            }?.title.replacingOccurrences(of: "File:", with: "")
        }
        guard let file else { return nil }

        // 3. Size and license from Commons.
        let fileTitle = "File:" + file
        guard let encoded = fileTitle.addingPercentEncoding(withAllowedCharacters: Self.querySafe),
              let info: CommonsQuery = await fetch("https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2&prop=imageinfo&iiprop=url%7Csize%7Cextmetadata&titles=\(encoded)"),
              let ii = info.query?.pages.first?.imageinfo?.first,
              let original = URL(string: ii.url) else { return nil }
        let meta = ii.extmetadata ?? [:]
        let license = Self.plain(meta["LicenseShortName"]?.value)
        guard !license.lowercased().contains("fair use"), !license.lowercased().contains("non-free") else { return nil }
        let credit = PhotoCredit(
            file: file,
            author: String(Self.plain(meta["Artist"]?.value).prefix(80)),
            license: license,
            licenseURL: meta["LicenseUrl"]?.value.flatMap { URL(string: Self.plain($0)) },
            pageURL: URL(string: ii.descriptionurl ?? "") ?? URL(string: "https://commons.wikimedia.org/wiki/\(Self.pathComponent(fileTitle))")!)
        return Source(original: original, width: ii.width ?? 0, credit: credit)
    }

    private func fetch<T: Decodable>(_ urlString: String) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        for attempt in 0..<4 {
            guard let (data, response) = try? await session.data(from: url) else { return nil }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 429 || status >= 500 {
                try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                continue
            }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }

    private func acquireLookup() async {
        if activeLookups < maxLookups {
            activeLookups += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseLookup() {
        if waiting.isEmpty {
            activeLookups -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    // MARK: Helpers

    private static let pathSafe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.()'")

    private static let querySafe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.~:()")

    private static func pathComponent(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: pathSafe) ?? title
    }

    /// ".../commons/a/ab/File.jpg" or ".../commons/thumb/a/ab/File.jpg/320px-File.jpg" -> "File.jpg"
    private static func fileName(fromUploadURL s: String) -> String? {
        guard let url = URL(string: s) else { return nil }
        let parts = url.pathComponents
        if let i = parts.firstIndex(of: "thumb"), parts.count > i + 3 { return parts[i + 3] }
        return parts.last
    }

    /// Original when it's already small enough; otherwise a standard-width Commons thumbnail.
    private static func url(for source: Source, width: Int) -> URL {
        // Wikimedia now appends tracking parameters (?utm_source=...) to file URLs; a thumbnail
        // path built on top of them is rejected, so drop the query first.
        var bare = URLComponents(url: source.original, resolvingAgainstBaseURL: false)
        bare?.query = nil
        let original = bare?.url ?? source.original
        if source.width > 0, source.width <= width { return original }
        var s = original.absoluteString
        guard let range = s.range(of: "/wikipedia/commons/") else { return original }
        s.replaceSubrange(range, with: "/wikipedia/commons/thumb/")
        let name = original.lastPathComponent
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? original.lastPathComponent
        let suffix = name.lowercased().hasSuffix(".svg") || name.lowercased().hasSuffix(".tif")
            || name.lowercased().hasSuffix(".tiff") ? ".png" : ""
        return URL(string: s + "/\(width)px-" + name + suffix) ?? original
    }

    /// Commons metadata is HTML; reduce it to plain text.
    private static func plain(_ html: String?) -> String {
        guard var s = html else { return "" }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: API shapes

    private struct Summary: Decodable {
        struct Image: Decodable { let source: String }
        let originalimage: Image?
    }

    private struct MediaList: Decodable {
        struct Item: Decodable {
            struct Src: Decodable { let src: String }
            let title: String
            let type: String
            let srcset: [Src]?
        }
        let items: [Item]
    }

    private struct CommonsQuery: Decodable {
        struct Query: Decodable { let pages: [Page] }
        struct Page: Decodable { let imageinfo: [Info]? }
        struct Info: Decodable {
            let url: String
            let descriptionurl: String?
            let width: Int?
            let extmetadata: [String: Meta]?
        }
        /// Values are almost always strings; anything else is ignored rather than failing the decode.
        struct Meta: Decodable {
            let value: String?
            private enum Key: CodingKey { case value }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                value = try? c.decode(String.self, forKey: .value)
            }
        }
        let query: Query?
    }
}
