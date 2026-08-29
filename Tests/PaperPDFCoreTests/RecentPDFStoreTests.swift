import Foundation
import Testing

@testable import PaperPDFCore

private enum FakeBookmarkError: Error {
  case unknownBookmark
}

private final class FakeBookmarkCodec: SecurityScopedBookmarkCoding {
  private var sequence = 0
  private var destinations: [Data: URL] = [:]
  var staleBookmarks: Set<Data> = []
  var unresolvableBookmarks: Set<Data> = []
  var bookmarkCreationFailures: Set<URL> = []
  private(set) var createdBookmarks: [Data] = []

  func createBookmark(for url: URL) throws -> Data {
    if bookmarkCreationFailures.contains(url) {
      throw FakeBookmarkError.unknownBookmark
    }
    sequence += 1
    let data = Data("bookmark-\(sequence)".utf8)
    destinations[data] = url
    createdBookmarks.append(data)
    return data
  }

  func resolveBookmark(_ data: Data) throws -> SecurityScopedBookmarkResolution {
    guard !unresolvableBookmarks.contains(data), let url = destinations[data] else {
      throw FakeBookmarkError.unknownBookmark
    }
    return SecurityScopedBookmarkResolution(
      url: url,
      isStale: staleBookmarks.contains(data)
    )
  }
}

@Test("A successful open is remembered even when bookmark creation fails")
func recentPDFFallsBackToItsStoredPath() throws {
  let temporaryRoot = try makeRecentPDFTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }

  let codec = FakeBookmarkCodec()
  let store = RecentPDFStore(
    storageURL: temporaryRoot.appendingPathComponent("recent.json"),
    bookmarkCodec: codec
  )
  let url = temporaryRoot.appendingPathComponent("fallback.pdf")
  try Data("%PDF fallback".utf8).write(to: url)
  codec.bookmarkCreationFailures.insert(url)

  try store.recordSuccessfulOpen(url)

  #expect(store.resolvedEntries().map(\.url) == [url])
}

@Test("Recent PDFs are newest-first, deduplicated, and capped at five")
func recentPDFOrderingAndLimit() throws {
  let temporaryRoot = try makeRecentPDFTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }

  let codec = FakeBookmarkCodec()
  let store = RecentPDFStore(
    storageURL: temporaryRoot.appendingPathComponent("recent.json"),
    bookmarkCodec: codec
  )
  var urls: [URL] = []
  for index in 0..<6 {
    let url = temporaryRoot.appendingPathComponent("book-\(index).pdf")
    try Data("%PDF book \(index)".utf8).write(to: url)
    urls.append(url)
    try store.recordSuccessfulOpen(
      url,
      at: Date(timeIntervalSince1970: TimeInterval(index))
    )
  }

  try store.recordSuccessfulOpen(
    urls[2],
    at: Date(timeIntervalSince1970: 100)
  )

  let entries = store.resolvedEntries()
  #expect(entries.count == 5)
  #expect(
    entries.map(\.displayName) == [
      "book-2.pdf", "book-5.pdf", "book-4.pdf", "book-3.pdf", "book-1.pdf",
    ])
  #expect(entries.first?.lastOpenedAt == Date(timeIntervalSince1970: 100))
}

@Test("Unavailable entries are preserved and broken bookmarks recover from path hints")
func recentPDFPreservesAndRepairsBookmarks() throws {
  let temporaryRoot = try makeRecentPDFTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }

  let codec = FakeBookmarkCodec()
  let store = RecentPDFStore(
    storageURL: temporaryRoot.appendingPathComponent("recent.json"),
    bookmarkCodec: codec
  )
  let validURL = temporaryRoot.appendingPathComponent("valid.pdf")
  let missingURL = temporaryRoot.appendingPathComponent("missing.pdf")
  let brokenURL = temporaryRoot.appendingPathComponent("broken.pdf")
  try Data("%PDF valid".utf8).write(to: validURL)
  try Data("%PDF missing".utf8).write(to: missingURL)
  try Data("%PDF broken".utf8).write(to: brokenURL)

  try store.recordSuccessfulOpen(validURL, at: Date(timeIntervalSince1970: 1))
  let validBookmark = try #require(codec.createdBookmarks.last)
  try store.recordSuccessfulOpen(missingURL, at: Date(timeIntervalSince1970: 2))
  let missingBookmark = try #require(codec.createdBookmarks.last)
  try store.recordSuccessfulOpen(brokenURL, at: Date(timeIntervalSince1970: 3))
  let brokenBookmark = try #require(codec.createdBookmarks.last)
  try FileManager.default.removeItem(at: missingURL)
  codec.unresolvableBookmarks.insert(missingBookmark)
  codec.unresolvableBookmarks.insert(brokenBookmark)
  codec.staleBookmarks.insert(validBookmark)

  let firstResolution = store.resolvedEntries()
  #expect(firstResolution.map(\.displayName) == ["broken.pdf", "valid.pdf"])
  #expect(codec.createdBookmarks.count == 5)  // broken and stale bookmarks were refreshed

  // The missing record was kept. Once the file returns, its path hint repairs
  // the unresolvable bookmark and the entry is visible again.
  try Data("%PDF missing again".utf8).write(to: missingURL)
  let secondResolution = store.resolvedEntries()
  #expect(
    secondResolution.map(\.displayName) == [
      "broken.pdf", "missing.pdf", "valid.pdf",
    ])
  #expect(codec.createdBookmarks.count == 6)
}

@Test("A corrupt recent-PDF archive is preserved for recovery")
func corruptRecentPDFArchiveIsPreserved() throws {
  let temporaryRoot = try makeRecentPDFTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }
  let storageURL = temporaryRoot.appendingPathComponent("recent.json")
  try Data("not-json".utf8).write(to: storageURL)

  let store = RecentPDFStore(
    storageURL: storageURL,
    bookmarkCodec: FakeBookmarkCodec()
  )

  #expect(store.resolvedEntries().isEmpty)
  #expect(try Data(contentsOf: storageURL) == Data("not-json".utf8))
}

private func makeRecentPDFTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
