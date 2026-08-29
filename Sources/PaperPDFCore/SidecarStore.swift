import CryptoKit
import Foundation

public struct SidecarStore: Sendable {
  public let rootDirectory: URL

  public init(rootDirectory: URL? = nil) {
    if let rootDirectory {
      self.rootDirectory = rootDirectory
    } else if let override = ProcessInfo.processInfo.environment["PAPERPDF_SIDECAR_DIR"],
      !override.isEmpty
    {
      self.rootDirectory = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.rootDirectory =
        applicationSupport
        .appendingPathComponent("PaperPDFPrototype", isDirectory: true)
        .appendingPathComponent("Sidecars", isDirectory: true)
    }
  }

  public func fingerprint(for pdfURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: pdfURL)
    defer { try? handle.close() }

    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hasher.update(data: data)
    }

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  public func sidecarURL(for pdfURL: URL) throws -> URL {
    let fingerprint = try fingerprint(for: pdfURL)
    return rootDirectory.appendingPathComponent("\(fingerprint).json")
  }

  public func load(for pdfURL: URL) throws -> (DocumentSidecar, URL) {
    let fingerprint = try fingerprint(for: pdfURL)
    let location = rootDirectory.appendingPathComponent("\(fingerprint).json")

    guard FileManager.default.fileExists(atPath: location.path) else {
      return (
        DocumentSidecar(
          sourceFilename: pdfURL.lastPathComponent,
          fingerprint: fingerprint
        ),
        location
      )
    }

    let data = try Data(contentsOf: location)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try decoder.decode(DocumentSidecar.self, from: data), location)
  }

  public func save(_ sidecar: DocumentSidecar, to location: URL) throws {
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(sidecar).write(to: location, options: .atomic)
  }
}
