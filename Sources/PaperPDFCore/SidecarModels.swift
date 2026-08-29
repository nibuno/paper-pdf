import Foundation

public enum StrokeKind: String, Codable, Equatable, Hashable, Sendable {
  case pencil
  case pen
  case highlighter
}

public struct StrokeColor: Codable, Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public static let graphite = StrokeColor(red: 0.16, green: 0.16, blue: 0.18)
  public static let highlighterYellow = StrokeColor(red: 1.0, green: 0.82, blue: 0.16)
}

public struct PDFPoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct InkStroke: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var pageIndex: Int
  public var points: [PDFPoint]
  public var lineWidth: Double
  // Optional so sidecars made before drawing tools were added still decode.
  public var kind: StrokeKind?
  public var color: StrokeColor?
  public var createdAt: Date

  public init(
    id: UUID = UUID(),
    pageIndex: Int,
    points: [PDFPoint],
    lineWidth: Double = 1.6,
    kind: StrokeKind = .pencil,
    color: StrokeColor = .graphite,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.pageIndex = pageIndex
    self.points = points
    self.lineWidth = lineWidth
    self.kind = kind
    self.color = color
    self.createdAt = createdAt
  }
}

public struct PageNote: Codable, Equatable, Sendable {
  public var pageIndex: Int
  public var text: String
  public var updatedAt: Date

  public init(pageIndex: Int, text: String, updatedAt: Date = Date()) {
    self.pageIndex = pageIndex
    self.text = text
    self.updatedAt = updatedAt
  }
}

public struct StickyNote: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var pageIndex: Int
  /// Center of the marker in PDF page coordinates.
  public var position: PDFPoint
  public var text: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    pageIndex: Int,
    position: PDFPoint,
    text: String = "",
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.pageIndex = pageIndex
    self.position = position
    self.text = text
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct DocumentSidecar: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var sourceFilename: String
  public var fingerprint: String
  public var strokes: [InkStroke]
  public var stickyNotes: [StickyNote]
  public var pageNotes: [Int: PageNote]
  public var pageVisits: [Int: Int]
  public var lastPageIndex: Int
  public var openedCount: Int
  public var updatedAt: Date

  public init(
    version: Int = DocumentSidecar.currentVersion,
    sourceFilename: String,
    fingerprint: String,
    strokes: [InkStroke] = [],
    stickyNotes: [StickyNote] = [],
    pageNotes: [Int: PageNote] = [:],
    pageVisits: [Int: Int] = [:],
    lastPageIndex: Int = 0,
    openedCount: Int = 0,
    updatedAt: Date = Date()
  ) {
    self.version = version
    self.sourceFilename = sourceFilename
    self.fingerprint = fingerprint
    self.strokes = strokes
    self.stickyNotes = stickyNotes
    self.pageNotes = pageNotes
    self.pageVisits = pageVisits
    self.lastPageIndex = lastPageIndex
    self.openedCount = openedCount
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case sourceFilename
    case fingerprint
    case strokes
    case stickyNotes
    case pageNotes
    case pageVisits
    case lastPageIndex
    case openedCount
    case updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    sourceFilename = try container.decode(String.self, forKey: .sourceFilename)
    fingerprint = try container.decode(String.self, forKey: .fingerprint)
    strokes = try container.decode([InkStroke].self, forKey: .strokes)
    // `stickyNotes` was added after the initial sidecar format. Missing means
    // the document simply had no sticky notes.
    stickyNotes = try container.decodeIfPresent([StickyNote].self, forKey: .stickyNotes) ?? []
    pageNotes = try container.decode([Int: PageNote].self, forKey: .pageNotes)
    pageVisits = try container.decode([Int: Int].self, forKey: .pageVisits)
    lastPageIndex = try container.decode(Int.self, forKey: .lastPageIndex)
    openedCount = try container.decode(Int.self, forKey: .openedCount)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }
}
