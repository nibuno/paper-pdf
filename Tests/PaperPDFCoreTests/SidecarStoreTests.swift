import Foundation
import Testing

@testable import PaperPDFCore

@Test("Sidecar data round-trips without modifying the source PDF")
func sidecarRoundTrip() throws {
  let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }

  let pdfURL = temporaryRoot.appendingPathComponent("book.pdf")
  let originalData = Data("%PDF-1.7\nprototype".utf8)
  try originalData.write(to: pdfURL)

  let store = SidecarStore(rootDirectory: temporaryRoot.appendingPathComponent("sidecars"))
  var (sidecar, location) = try store.load(for: pdfURL)
  let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
  sidecar.updatedAt = fixedDate
  sidecar.strokes.append(
    InkStroke(
      pageIndex: 2,
      points: [PDFPoint(x: 10, y: 20), PDFPoint(x: 30, y: 21)],
      lineWidth: 13,
      kind: .highlighter,
      color: StrokeColor(red: 0.95, green: 0.7, blue: 0.1),
      createdAt: fixedDate
    )
  )
  sidecar.stickyNotes.append(
    StickyNote(
      pageIndex: 2,
      position: PDFPoint(x: 180, y: 320),
      text: "型消去を復習する",
      createdAt: fixedDate,
      updatedAt: fixedDate
    )
  )
  sidecar.pageNotes[2] = PageNote(
    pageIndex: 2,
    text: "Genericsの章を再読する",
    updatedAt: fixedDate
  )
  try store.save(sidecar, to: location)

  let (reloaded, _) = try store.load(for: pdfURL)
  #expect(reloaded == sidecar)
  #expect(try Data(contentsOf: pdfURL) == originalData)
}

@Test("Sidecars created before sticky notes still decode with an empty note list")
func legacySidecarWithoutStickyNotesDecodes() throws {
  let json = #"""
  {
    "version":1,
    "sourceFilename":"book.pdf",
    "fingerprint":"abc123",
    "strokes":[],
    "pageNotes":{},
    "pageVisits":{"0":2},
    "lastPageIndex":0,
    "openedCount":1,
    "updatedAt":"2023-11-14T22:13:20Z"
  }
  """#
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601

  let sidecar = try decoder.decode(DocumentSidecar.self, from: Data(json.utf8))

  #expect(sidecar.stickyNotes.isEmpty)
  #expect(sidecar.pageVisits[0] == 2)
}

@Test("Sidecars from the pencil-only version still decode")
func legacyStrokeDecodes() throws {
  let json = #"{"id":"3E727EDD-D969-4E44-B775-213C7433A287","pageIndex":1,"points":[{"x":10,"y":20},{"x":30,"y":40}],"lineWidth":1.6,"createdAt":"2023-11-14T22:13:20Z"}"#
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601

  let stroke = try decoder.decode(InkStroke.self, from: Data(json.utf8))

  #expect(stroke.kind == nil)
  #expect(stroke.color == nil)
}

@Test("A moved PDF keeps the same content fingerprint")
func fingerprintSurvivesMove() throws {
  let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporaryRoot) }

  let firstURL = temporaryRoot.appendingPathComponent("first.pdf")
  let secondURL = temporaryRoot.appendingPathComponent("second.pdf")
  try Data("same PDF bytes".utf8).write(to: firstURL)
  try FileManager.default.copyItem(at: firstURL, to: secondURL)

  let store = SidecarStore(rootDirectory: temporaryRoot.appendingPathComponent("sidecars"))
  #expect(try store.fingerprint(for: firstURL) == store.fingerprint(for: secondURL))
}
