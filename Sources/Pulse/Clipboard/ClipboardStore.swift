import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Persists clipboard history: metadata + text in SQLite, images as PNG files beside it.
///
/// All I/O, hashing and image encoding run on one serial utility-QoS queue, which macOS schedules
/// on the efficiency cores. Results are delivered back on the main thread.
final class ClipboardStore: @unchecked Sendable {
    let imagesDirectory: URL
    private let databaseURL: URL
    private let maxItems: Int
    private let queue = DispatchQueue(label: "Pulse.ClipboardStore", qos: .utility)
    private var database: SQLiteDatabase? // queue-confined

    init(maxItems: Int) {
        self.maxItems = maxItems
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        imagesDirectory = support.appendingPathComponent("Images", isDirectory: true)
        databaseURL = support.appendingPathComponent("clipboard.sqlite")

        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
                let database = try SQLiteDatabase(url: databaseURL)
                try database.execute("""
                    CREATE TABLE IF NOT EXISTS items (
                        id TEXT PRIMARY KEY,
                        kind INTEGER NOT NULL,
                        text TEXT,
                        image_file TEXT,
                        width INTEGER,
                        height INTEGER,
                        hash TEXT NOT NULL UNIQUE,
                        source TEXT,
                        created REAL NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS items_created ON items (created DESC);
                    """)
                try Self.migrate(database)
                self.database = database
            } catch {
                NSLog("Pulse: clipboard store unavailable: \(error)")
            }
        }
    }

    func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    /// Column list matching `item(from:)`.
    private static let columns = "id, kind, text, image_file, width, height, hash, source, created, pinned"

    /// Schema changes since the first release, tracked in `PRAGMA user_version`.
    private static func migrate(_ database: SQLiteDatabase) throws {
        var version: Int64 = 0
        try database.query("PRAGMA user_version") { version = $0.int(0) ?? 0 }
        if version < 1 {
            // Pin time (seconds since 1970), NULL when not pinned.
            try database.execute("ALTER TABLE items ADD COLUMN pinned REAL; PRAGMA user_version = 1;")
        }
    }

    // MARK: - Reads

    /// Every pinned item plus the newest `maxItems` unpinned ones, newest first.
    func loadAll(completion: @escaping @MainActor ([ClipItem]) -> Void) {
        queue.async { [self] in
            var items: [ClipItem] = []
            try? database?.query(
                "SELECT \(Self.columns) FROM items WHERE pinned IS NOT NULL",
                []
            ) { row in
                if let item = Self.item(from: row) { items.append(item) }
            }
            try? database?.query(
                "SELECT \(Self.columns) FROM items WHERE pinned IS NULL ORDER BY created DESC LIMIT ?",
                [.int(Int64(maxItems))]
            ) { row in
                if let item = Self.item(from: row) { items.append(item) }
            }
            items.sort { $0.date > $1.date }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(items) } }
        }
    }

    // MARK: - Writes

    /// Records a capture. Duplicates (same content hash) are moved to the top instead of stored twice.
    /// `completion` receives the resulting item and the ids of any items pruned to stay under the limit.
    func record(_ capture: ClipCapture, sourceBundleID: String?, completion: @escaping @MainActor (ClipItem, [String]) -> Void) {
        queue.async { [self] in
            guard let database else { return }
            let now = Date()
            let hash = Self.hash(of: capture)

            do {
                var existing: ClipItem?
                try database.query(
                    "SELECT \(Self.columns) FROM items WHERE hash = ?",
                    [.text(hash)]
                ) { row in existing = Self.item(from: row) }

                let item: ClipItem
                if var existing {
                    existing.date = now
                    try database.run("UPDATE items SET created = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .text(existing.id)])
                    item = existing
                } else {
                    guard let created = try makeItem(from: capture, hash: hash, source: sourceBundleID, date: now) else { return }
                    try database.run(
                        "INSERT INTO items (id, kind, text, image_file, width, height, hash, source, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        [
                            .text(created.id), .int(Int64(created.kind.rawValue)), .text(created.text), .text(created.imageFile),
                            .int(created.pixelSize.map { Int64($0.width) }), .int(created.pixelSize.map { Int64($0.height) }),
                            .text(created.hash), .text(created.sourceBundleID), .double(now.timeIntervalSince1970),
                        ]
                    )
                    item = created
                }

                let pruned = try prune(database)
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(item, pruned) } }
            } catch {
                NSLog("Pulse: failed to record clipboard item: \(error)")
            }
        }
    }

    func delete(id: String) {
        queue.async { [self] in
            guard let database else { return }
            var file: String?
            try? database.query("SELECT image_file FROM items WHERE id = ?", [.text(id)]) { file = $0.text(0) }
            try? database.run("DELETE FROM items WHERE id = ?", [.text(id)])
            if let file { try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file)) }
        }
    }

    func setPinned(id: String, at date: Date?) {
        queue.async { [self] in
            try? database?.run("UPDATE items SET pinned = ? WHERE id = ?", [date.map { .double($0.timeIntervalSince1970) } ?? .int(nil), .text(id)])
        }
    }

    /// Deletes every item that isn't pinned.
    func deleteUnpinned() {
        queue.async { [self] in
            guard let database else { return }
            var files: [String] = []
            try? database.query("SELECT image_file FROM items WHERE pinned IS NULL AND image_file IS NOT NULL") { row in
                if let file = row.text(0) { files.append(file) }
            }
            try? database.run("DELETE FROM items WHERE pinned IS NULL")
            for file in files { try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file)) }
        }
    }

    // MARK: - Helpers (queue)

    private func makeItem(from capture: ClipCapture, hash: String, source: String?, date: Date) throws -> ClipItem? {
        let id = UUID().uuidString
        switch capture {
        case .text(let text):
            return ClipItem(id: id, kind: .text, text: text, imageFile: nil, pixelSize: nil, hash: hash, sourceBundleID: source, date: date)
        case .files(let urls):
            let paths = urls.map(\.path).joined(separator: "\n")
            return ClipItem(id: id, kind: .files, text: paths, imageFile: nil, pixelSize: nil, hash: hash, sourceBundleID: source, date: date)
        case .image(let data, let isPNG):
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let fileName = "\(id).png"
            let url = imagesDirectory.appendingPathComponent(fileName)
            if isPNG {
                try data.write(to: url, options: .atomic) // already PNG: store as-is, no re-encode
            } else {
                // TIFF is uncompressed and huge; transcode once to PNG.
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImageFromSource(destination, imageSource, 0, nil)
                guard CGImageDestinationFinalize(destination) else { return nil }
            }
            return ClipItem(
                id: id, kind: .image, text: nil, imageFile: fileName,
                pixelSize: CGSize(width: width, height: height), hash: hash, sourceBundleID: source, date: date
            )
        }
    }

    private func prune(_ database: SQLiteDatabase) throws -> [String] {
        var doomed: [(id: String, file: String?)] = []
        try database.query(
            // Pinned items don't count toward the limit and are never pruned.
            "SELECT id, image_file FROM items WHERE pinned IS NULL ORDER BY created DESC LIMIT -1 OFFSET ?",
            [.int(Int64(maxItems))]
        ) { row in
            if let id = row.text(0) { doomed.append((id, row.text(1))) }
        }
        for entry in doomed {
            try database.run("DELETE FROM items WHERE id = ?", [.text(entry.id)])
            if let file = entry.file { try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file)) }
        }
        return doomed.map(\.id)
    }

    private static func hash(of capture: ClipCapture) -> String {
        let digest: SHA256.Digest
        switch capture {
        case .text(let text): digest = SHA256.hash(data: Data("t:\(text)".utf8))
        case .files(let urls): digest = SHA256.hash(data: Data("f:\(urls.map(\.path).joined(separator: "\n"))".utf8))
        case .image(let data, _): digest = SHA256.hash(data: data)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func item(from row: SQLiteDatabase.Row) -> ClipItem? {
        guard let id = row.text(0), let kind = ClipItem.Kind(rawValue: Int(row.int(1) ?? -1)), let hash = row.text(6) else { return nil }
        var size: CGSize?
        if let width = row.int(4), let height = row.int(5) { size = CGSize(width: Int(width), height: Int(height)) }
        return ClipItem(
            id: id, kind: kind, text: row.text(2), imageFile: row.text(3), pixelSize: size,
            hash: hash, sourceBundleID: row.text(7), date: Date(timeIntervalSince1970: row.double(8)),
            pinnedDate: row.int(9) == nil ? nil : Date(timeIntervalSince1970: row.double(9))
        )
    }
}
