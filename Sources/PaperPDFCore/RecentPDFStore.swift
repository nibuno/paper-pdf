import CryptoKit
import Foundation

public struct RecentPDFRecord: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var bookmarkData: Data
  public var identityKey: String
  public var displayName: String
  public var pathHint: String
  public var lastOpenedAt: Date

  public init(
    id: UUID = UUID(),
    bookmarkData: Data,
    identityKey: String,
    displayName: String,
    pathHint: String,
    lastOpenedAt: Date
  ) {
    self.id = id
    self.bookmarkData = bookmarkData
    self.identityKey = identityKey
    self.displayName = displayName
    self.pathHint = pathHint
    self.lastOpenedAt = lastOpenedAt
  }
}

public struct ResolvedRecentPDF: Identifiable, Equatable, Sendable {
  public var id: UUID
  public var url: URL
  public var displayName: String
  public var pathHint: String
  public var lastOpenedAt: Date

  public init(record: RecentPDFRecord, url: URL) {
    id = record.id
    self.url = url
    displayName = record.displayName
    pathHint = record.pathHint
    lastOpenedAt = record.lastOpenedAt
  }
}

public struct SecurityScopedBookmarkResolution: Sendable {
  public var url: URL
  public var isStale: Bool

  public init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }
}

public protocol SecurityScopedBookmarkCoding {
  func createBookmark(for url: URL) throws -> Data
  func resolveBookmark(_ data: Data) throws -> SecurityScopedBookmarkResolution
}

public struct SystemSecurityScopedBookmarkCodec: SecurityScopedBookmarkCoding {
  public init() {}

  public func createBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  public func resolveBookmark(_ data: Data) throws -> SecurityScopedBookmarkResolution {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    return SecurityScopedBookmarkResolution(url: url, isStale: isStale)
  }
}

private struct RecentPDFArchive: Codable {
  static let currentVersion = 1

  var version = currentVersion
  var entries: [RecentPDFRecord]
}

private struct RecentPDFRecordResolution {
  var url: URL
  var shouldRefreshBookmark: Bool
}

public final class RecentPDFStore {
  public static let maximumEntryCount = 5

  public let storageURL: URL
  private let bookmarkCodec: any SecurityScopedBookmarkCoding
  private let fileManager: FileManager

  public init(
    storageURL: URL,
    bookmarkCodec: any SecurityScopedBookmarkCoding = SystemSecurityScopedBookmarkCodec(),
    fileManager: FileManager = .default
  ) {
    self.storageURL = storageURL
    self.bookmarkCodec = bookmarkCodec
    self.fileManager = fileManager
  }

  public static func applicationDefault() -> RecentPDFStore {
    if let override = ProcessInfo.processInfo.environment["PAPERPDF_RECENTS_FILE"],
      !override.isEmpty
    {
      return RecentPDFStore(storageURL: URL(fileURLWithPath: override))
    }

    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let storageURL =
      applicationSupport
      .appendingPathComponent("PaperPDFPrototype", isDirectory: true)
      .appendingPathComponent("recent-pdfs.json")
    return RecentPDFStore(storageURL: storageURL)
  }

  /// Saves a successful open. The identity hash is only used for deduplication;
  /// reopening prefers `bookmarkData` and uses the stored directory and file
  /// name only when a rebuilt app cannot resolve that bookmark.
  public func recordSuccessfulOpen(_ url: URL, at date: Date = Date()) throws {
    // The display path is also a recovery route in this non-sandboxed app, so
    // a transient bookmark creation failure must not drop the history event.
    let bookmarkData = (try? bookmarkCodec.createBookmark(for: url)) ?? Data()
    let identityKey = identityKey(for: url)
    var entries = loadRecordsRecoveringFromCorruption()
    entries.removeAll { $0.identityKey == identityKey }
    entries.append(
      makeRecord(
        for: url,
        bookmarkData: bookmarkData,
        identityKey: identityKey,
        date: date
      )
    )
    entries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    if entries.count > Self.maximumEntryCount {
      entries.removeLast(entries.count - Self.maximumEntryCount)
    }
    try save(entries)
  }

  /// Resolves all entries without deleting records that are temporarily
  /// unavailable. Rebuilt ad-hoc apps can briefly fail to resolve old
  /// security-scoped bookmarks; that must not erase the user's history.
  public func resolvedEntries() -> [ResolvedRecentPDF] {
    let records = loadRecordsRecoveringFromCorruption()
      .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    var repairedRecords = records
    var resolvedEntries: [ResolvedRecentPDF] = []
    var seenIdentities: Set<String> = []

    for index in repairedRecords.indices {
      var record = repairedRecords[index]
      guard let resolution = resolve(record) else { continue }

      let resolvedIdentity = identityKey(for: resolution.url)
      guard seenIdentities.insert(resolvedIdentity).inserted else { continue }

      if resolution.shouldRefreshBookmark,
        let refreshedBookmark = refreshedBookmark(for: resolution.url)
      {
        record.bookmarkData = refreshedBookmark
      }
      record.identityKey = resolvedIdentity
      record.displayName = resolution.url.lastPathComponent
      record.pathHint = pathHint(for: resolution.url)
      repairedRecords[index] = record
      resolvedEntries.append(ResolvedRecentPDF(record: record, url: resolution.url))
      if resolvedEntries.count == Self.maximumEntryCount {
        continue
      }
    }

    if repairedRecords != records {
      try? save(repairedRecords)
    }
    return Array(resolvedEntries.prefix(Self.maximumEntryCount))
  }

  /// Resolves one history item exclusively from its bookmark data.
  public func resolveEntry(id: UUID) -> ResolvedRecentPDF? {
    var records = loadRecordsRecoveringFromCorruption()
    guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
    var record = records[index]

    guard let resolution = resolve(record) else { return nil }

    if resolution.shouldRefreshBookmark,
      let refreshedBookmark = refreshedBookmark(for: resolution.url)
    {
      record.bookmarkData = refreshedBookmark
    }
    record.identityKey = identityKey(for: resolution.url)
    record.displayName = resolution.url.lastPathComponent
    record.pathHint = pathHint(for: resolution.url)
    records[index] = record
    try? save(records)
    return ResolvedRecentPDF(record: record, url: resolution.url)
  }

  public func clear() throws {
    try save([])
  }

  private func loadRecordsRecoveringFromCorruption() -> [RecentPDFRecord] {
    guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
    do {
      let data = try Data(contentsOf: storageURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(RecentPDFArchive.self, from: data).entries
    } catch {
      // Keep the original bytes for recovery. A later successful open can
      // replace the archive, but merely showing the start screen must not.
      return []
    }
  }

  private func save(_ entries: [RecentPDFRecord]) throws {
    try fileManager.createDirectory(
      at: storageURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(RecentPDFArchive(entries: entries))
    try data.write(to: storageURL, options: .atomic)
  }

  private func isExistingPDF(_ url: URL) -> Bool {
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    var isDirectory: ObjCBool = false
    return url.pathExtension.lowercased() == "pdf"
      && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private func resolve(_ record: RecentPDFRecord) -> RecentPDFRecordResolution? {
    if let bookmarkResolution = try? bookmarkCodec.resolveBookmark(record.bookmarkData),
      isExistingPDF(bookmarkResolution.url)
    {
      return RecentPDFRecordResolution(
        url: bookmarkResolution.url,
        shouldRefreshBookmark: bookmarkResolution.isStale
      )
    }

    // `pathHint` is persisted for display and gives a safe local fallback for
    // this non-sandboxed app. It also lets a rebuilt ad-hoc bundle repair a
    // bookmark whose signing identity is no longer accepted by macOS.
    let directoryPath = (record.pathHint as NSString).expandingTildeInPath
    guard !directoryPath.isEmpty, !record.displayName.isEmpty else { return nil }
    let fallbackURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
      .appendingPathComponent(record.displayName)
    guard isExistingPDF(fallbackURL) else { return nil }

    return RecentPDFRecordResolution(
      url: fallbackURL,
      shouldRefreshBookmark: true
    )
  }

  private func refreshedBookmark(for url: URL) -> Data? {
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try? bookmarkCodec.createBookmark(for: url)
  }

  private func makeRecord(
    for url: URL,
    bookmarkData: Data,
    identityKey: String,
    date: Date
  ) -> RecentPDFRecord {
    RecentPDFRecord(
      bookmarkData: bookmarkData,
      identityKey: identityKey,
      displayName: url.lastPathComponent,
      pathHint: pathHint(for: url),
      lastOpenedAt: date
    )
  }

  private func identityKey(for url: URL) -> String {
    let path = url.standardizedFileURL.path
    return SHA256.hash(data: Data(path.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func pathHint(for url: URL) -> String {
    (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
  }
}
