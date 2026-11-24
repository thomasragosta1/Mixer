import CryptoKit
import Foundation

/// Keeps the animal library current without an App Store update.
///
/// The app ships with `animals.json` and `photos.json` in its bundle, so it always works
/// offline. When online, it fetches the same two files from the project's public repository
/// (one small conditional request each, at most every few hours). If the published library
/// differs from what's installed, the new one is saved to disk and used from then on. Adding
/// animals is therefore just a matter of publishing an updated `animals.json`.
enum ContentSync {
    /// Where the published content lives: the files in this repository, served by GitHub.
    static let baseURL = URL(string: "https://raw.githubusercontent.com/thomasragosta1/Mixer/claude/wizardly-cray-v2bapl/Fauna/Fauna/Resources/")!

    /// How often to look for new content.
    static let checkInterval: TimeInterval = 6 * 60 * 60

    private static let lastCheckKey = "ContentSync.lastCheck"
    private static let etagKey = "ContentSync.etag."
    private static let bundleHashKey = "ContentSync.bundleHash"

    static var directory: URL? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true) else { return nil }
        let dir = support.appendingPathComponent("Content", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Loading

    /// The library to start with: the downloaded one if it's newer than this build's bundle,
    /// otherwise the bundled one.
    static func initialLibrary(bundle: Bundle = .main) -> [Animal] {
        if let cached = cachedFile("animals.json", bundle: bundle),
           let animals = decodeLibrary(cached) {
            return animals
        }
        return AnimalLibrary.load(bundle: bundle)
    }

    /// Photo credits and files published alongside the library, if a newer copy was downloaded.
    static func cachedPhotos(bundle: Bundle = .main) -> Data? {
        cachedFile("photos.json", bundle: bundle)
    }

    /// A downloaded file, but only if it was downloaded while this same build was installed.
    /// After an app update the bundle may be newer than an old download, so start fresh.
    private static func cachedFile(_ name: String, bundle: Bundle) -> Data? {
        guard let dir = directory,
              UserDefaults.standard.string(forKey: bundleHashKey) == bundleHash(bundle: bundle),
              let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return data
    }

    static func bundleHash(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "animals", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return "" }
        return hash(data)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A library is only accepted if it decodes and looks complete: never replace a good
    /// library with a truncated or half-written one.
    static func decodeLibrary(_ data: Data, minimumCount: Int = 20) -> [Animal]? {
        guard let animals = try? JSONDecoder().decode([Animal].self, from: data),
              animals.count >= minimumCount,
              Set(animals.map(\.id)).count == animals.count,
              animals.allSatisfy({ !$0.quiz.isEmpty && $0.quiz.allSatisfy { $0.choices.count >= 2 } })
        else { return nil }
        return animals
    }

    // MARK: Syncing

    struct Update {
        var animals: [Animal]?
        var photos: Data?
    }

    /// Checks for new content. Returns what changed, or nil when there's nothing new, it's too
    /// soon to check again, or the network isn't available.
    static func check(force: Bool = false, session: URLSession = .shared, bundle: Bundle = .main) async -> Update? {
        let defaults = UserDefaults.standard
        let now = Date()
        if !force, let last = defaults.object(forKey: lastCheckKey) as? Date, now.timeIntervalSince(last) < checkInterval {
            return nil
        }
        guard let dir = directory else { return nil }
        // Downloads from an older build are dropped (see cachedFile), so their ETags must go too.
        let currentBundle = bundleHash(bundle: bundle)
        if defaults.string(forKey: bundleHashKey) != currentBundle {
            for name in ["animals.json", "photos.json"] {
                defaults.removeObject(forKey: etagKey + name)
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
            defaults.set(currentBundle, forKey: bundleHashKey)
        }

        var update = Update()
        if let data = await fetch("animals.json", session: session) {
            let bundled = bundle.url(forResource: "animals", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            if hash(data) != bundled.map(hash), let animals = decodeLibrary(data) {
                try? data.write(to: dir.appendingPathComponent("animals.json"), options: .atomic)
                update.animals = animals
            }
        }
        if let data = await fetch("photos.json", session: session),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            try? data.write(to: dir.appendingPathComponent("photos.json"), options: .atomic)
            update.photos = data
        }
        defaults.set(now, forKey: lastCheckKey)
        return update.animals == nil && update.photos == nil ? nil : update
    }

    /// A conditional GET: returns the body only when the file changed since the last fetch.
    private static func fetch(_ name: String, session: URLSession) async -> Data? {
        var request = URLRequest(url: baseURL.appendingPathComponent(name),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let key = etagKey + name
        if let etag = UserDefaults.standard.string(forKey: key) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: key)
        }
        return data
    }
}
