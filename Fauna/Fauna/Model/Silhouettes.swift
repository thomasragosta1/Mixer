import UIKit

/// Side-view silhouettes from PhyloPic (phylopic.org), bundled as `sil-<id>.png` with their
/// credits in `silhouettes.json`. Some animals use a close relative's silhouette.
enum Silhouettes {
    struct Credit: Decodable, Hashable {
        let author: String
        let license: String
        let licenseURL: String
        let page: String
        let taxon: String
        let match: String
    }

    static let credits: [String: Credit] = {
        guard let url = Bundle.main.url(forResource: "silhouettes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Credit].self, from: data)) ?? [:]
    }()

    static func image(for id: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "sil-\(id)", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// "Silhouette: Jagged Fang Designs, CC0, via PhyloPic" (noting when it's a relative's).
    static func creditLine(for id: String) -> String? {
        guard let c = credits[id] else { return nil }
        let relative = c.match.hasPrefix("species") ? "" : " (\(c.taxon))"
        return "Silhouette\(relative): \(c.author), \(c.license), via PhyloPic."
    }
}
