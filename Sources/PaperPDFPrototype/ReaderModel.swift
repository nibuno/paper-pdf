import AppKit
import Combine
import Foundation
import PDFKit
import PaperPDFCore

enum InteractionMode: String, CaseIterable, Identifiable {
  case reading = "読む"
  case pencil = "鉛筆"
  case pen = "ペン"
  case highlighter = "蛍光ペン"
  case eraser = "消しゴム"
  case stickyNote = "付箋"

  var id: Self { self }

  var isDrawing: Bool {
    switch self {
    case .pencil, .pen, .highlighter: true
    case .reading, .eraser, .stickyNote: false
    }
  }

  var editsAnnotations: Bool {
    self != .reading
  }

  var allowsColorSelection: Bool {
    self == .pencil || self == .pen
  }

  var symbolName: String {
    switch self {
    case .reading: "text.cursor"
    case .pencil: "pencil"
    case .pen: "pencil.tip"
    case .highlighter: "highlighter"
    case .eraser: "eraser"
    case .stickyNote: "note.text"
    }
  }

  var strokeKind: StrokeKind? {
    switch self {
    case .reading: nil
    case .pencil: .pencil
    case .pen: .pen
    case .highlighter: .highlighter
    case .eraser: nil
    case .stickyNote: nil
    }
  }

  var lineWidth: Double {
    switch self {
    case .reading: 0
    case .pencil: 1.6
    case .pen: 2.4
    case .highlighter: 13
    case .eraser: 0
    case .stickyNote: 0
    }
  }
}

enum ReadingLayout: String, CaseIterable, Identifiable {
  case continuous
  case singlePage
  case twoPage

  var id: Self { self }

  var label: String {
    switch self {
    case .continuous: "連続"
    case .singlePage: "1ページ"
    case .twoPage: "見開き"
    }
  }

  var isPaged: Bool {
    self != .continuous
  }
}

struct PDFPermissionSummary {
  var isEncrypted = false
  var isLocked = false
  var allowsCopying = false
  var allowsCommenting = false
  var allowsDocumentChanges = false
}

@MainActor
final class ReaderModel: ObservableObject {
  @Published private(set) var document: PDFDocument?
  @Published private(set) var documentURL: URL?
  @Published private(set) var documentFingerprint = ""
  @Published private(set) var sidecarURL: URL?
  @Published private(set) var strokes: [InkStroke] = []
  @Published private(set) var stickyNotes: [StickyNote] = []
  @Published private(set) var selectedStickyNoteID: UUID?
  @Published private(set) var pageNotes: [Int: PageNote] = [:]
  @Published private(set) var pageVisits: [Int: Int] = [:]
  @Published private(set) var currentPageIndex = 0
  @Published private(set) var pageCount = 0
  @Published private(set) var selectedText = ""
  @Published private(set) var permissions = PDFPermissionSummary()
  @Published private(set) var recentPDFs: [ResolvedRecentPDF] = []
  @Published var interactionMode: InteractionMode = .reading {
    didSet {
      if oldValue.allowsColorSelection, let previousKind = oldValue.strokeKind {
        drawingColors[previousKind] = drawingColor
      }
      if interactionMode.allowsColorSelection, let currentKind = interactionMode.strokeKind {
        drawingColor = drawingColors[currentKind] ?? drawingColor
      }
    }
  }
  @Published var drawingColor = StrokeColor.graphite
  @Published var readingLayout: ReadingLayout = .continuous {
    didSet {
      UserDefaults.standard.set(readingLayout.rawValue, forKey: "readingLayout")
    }
  }
  @Published private(set) var zoomScaleFactor: CGFloat = 1
  @Published private(set) var statusMessage = "PDFを開いてください"

  private let store = SidecarStore()
  private let recentPDFStore: RecentPDFStore
  private var sidecar: DocumentSidecar?
  private var restoreTargetPageIndex: Int?
  private var commandLineDocumentOpenWasChecked = false
  private var securityScopedURL: URL?
  private var hasSecurityScopedAccess = false
  private var drawingColors: [StrokeKind: StrokeColor] = [
    .pencil: .graphite,
    .pen: StrokeColor(red: 0.08, green: 0.28, blue: 0.72),
  ]
  private var zoomInAction: (() -> Void)?
  private var zoomOutAction: (() -> Void)?
  private var fitToViewAction: (() -> Void)?
  private var setZoomAction: ((CGFloat) -> Void)?
  private var goToPageAction: ((Int) -> Void)?

  init(recentPDFStore: RecentPDFStore = .applicationDefault()) {
    self.recentPDFStore = recentPDFStore
    if let savedLayout = UserDefaults.standard.string(forKey: "readingLayout"),
      let layout = ReadingLayout(rawValue: savedLayout)
    {
      readingLayout = layout
    }
    recentPDFs = recentPDFStore.resolvedEntries()
  }

  deinit {
    if hasSecurityScopedAccess {
      securityScopedURL?.stopAccessingSecurityScopedResource()
    }
  }

  @discardableResult
  func openDocument(at url: URL) -> Bool {
    let newURLHasSecurityScopedAccess = url.startAccessingSecurityScopedResource()

    guard let loadedDocument = PDFDocument(url: url) else {
      statusMessage = "PDFを開けませんでした: \(url.lastPathComponent)"
      if newURLHasSecurityScopedAccess {
        url.stopAccessingSecurityScopedResource()
      }
      return false
    }

    do {
      let (loadedSidecar, location) = try store.load(for: url)

      // Keep the previous document's access alive until the replacement has
      // been fully loaded. Starting first also keeps same-URL reopen calls
      // balanced when the security scope is reference counted by the system.
      if hasSecurityScopedAccess, let securityScopedURL {
        securityScopedURL.stopAccessingSecurityScopedResource()
      }
      securityScopedURL = url
      hasSecurityScopedAccess = newURLHasSecurityScopedAccess

      sidecar = loadedSidecar
      documentFingerprint = loadedSidecar.fingerprint
      sidecarURL = location
      strokes = loadedSidecar.strokes
      stickyNotes = loadedSidecar.stickyNotes
      selectedStickyNoteID = nil
      pageNotes = loadedSidecar.pageNotes
      pageVisits = loadedSidecar.pageVisits
      currentPageIndex = min(
        max(loadedSidecar.lastPageIndex, 0),
        max(loadedDocument.pageCount - 1, 0)
      )

      documentURL = url
      document = loadedDocument
      pageCount = loadedDocument.pageCount
      permissions = PDFPermissionSummary(
        isEncrypted: loadedDocument.isEncrypted,
        isLocked: loadedDocument.isLocked,
        allowsCopying: loadedDocument.allowsCopying,
        allowsCommenting: loadedDocument.allowsCommenting,
        allowsDocumentChanges: loadedDocument.allowsDocumentChanges
      )

      statusMessage =
        loadedDocument.isLocked
        ? "このPDFはロックされているため、読み取り専用で開きました"
        : "線やメモは自動保存されます"
      pageVisits[currentPageIndex, default: 0] += 1
      sidecar?.openedCount += 1
      sidecar?.pageVisits = pageVisits
      sidecar?.updatedAt = Date()
      saveSidecar()

      rememberSuccessfulOpen(url)
      return true
    } catch {
      statusMessage = "線やメモの保存先を準備できませんでした: \(error.localizedDescription)"
      if newURLHasSecurityScopedAccess {
        url.stopAccessingSecurityScopedResource()
      }
      return false
    }
  }

  func configureZoomActions(
    zoomIn: @escaping () -> Void,
    zoomOut: @escaping () -> Void,
    fitToView: @escaping () -> Void,
    setZoom: @escaping (CGFloat) -> Void
  ) {
    zoomInAction = zoomIn
    zoomOutAction = zoomOut
    fitToViewAction = fitToView
    setZoomAction = setZoom
  }

  func configurePageNavigation(_ goToPage: @escaping (Int) -> Void) {
    goToPageAction = goToPage
  }

  func zoomIn() {
    zoomInAction?()
  }

  func zoomOut() {
    zoomOutAction?()
  }

  func fitToView() {
    fitToViewAction?()
  }

  func setZoomScale(_ scale: CGFloat) {
    setZoomAction?(scale)
  }

  func updateZoomScale(_ scale: CGFloat) {
    guard scale.isFinite, scale > 0 else { return }
    zoomScaleFactor = scale
  }

  var activeDrawingColor: StrokeColor {
    interactionMode == .highlighter ? .highlighterYellow : drawingColor
  }

  func openCommandLineDocumentIfNeeded() {
    guard !commandLineDocumentOpenWasChecked else { return }
    commandLineDocumentOpenWasChecked = true

    if let argument = CommandLine.arguments.dropFirst().first(where: {
      URL(fileURLWithPath: $0).pathExtension.lowercased() == "pdf"
    }) {
      let commandLineURL = URL(fileURLWithPath: argument)
      if documentURL?.standardizedFileURL != commandLineURL.standardizedFileURL {
        openDocument(at: commandLineURL)
      }
    }
  }

  func handleOpenURL(_ url: URL) {
    if document != nil,
      documentURL?.standardizedFileURL == url.standardizedFileURL
    {
      return
    }
    openDocument(at: url)
  }

  func openRecentPDF(id: UUID) {
    guard let resolved = recentPDFStore.resolveEntry(id: id) else {
      recentPDFs = recentPDFStore.resolvedEntries()
      statusMessage = "最近開いたPDFを見つけられなかったため、履歴から除外しました"
      return
    }
    openDocument(at: resolved.url)
  }

  func clearRecentPDFs() {
    do {
      try recentPDFStore.clear()
      recentPDFs = []
      statusMessage = "最近開いたPDFの履歴を消去しました"
    } catch {
      statusMessage = "最近開いたPDFの履歴を消去できませんでした"
    }
  }

  func setCurrentPage(_ index: Int) {
    guard index >= 0, index < pageCount else { return }
    if let restoreTargetPageIndex {
      guard index == restoreTargetPageIndex else { return }
      self.restoreTargetPageIndex = nil
      // Opening the document already recorded this page visit. PDFKit emits a
      // second page-change notification while restoring the saved position;
      // accepting the position without counting it prevents a first open from
      // looking like a reread.
      currentPageIndex = index
      sidecar?.lastPageIndex = index
      return
    }
    guard index != currentPageIndex else { return }

    currentPageIndex = index
    pageVisits[index, default: 0] += 1
    sidecar?.lastPageIndex = index
    sidecar?.pageVisits = pageVisits
    sidecar?.updatedAt = Date()
    saveSidecar()
  }

  func beginRestoringPage(to index: Int) {
    restoreTargetPageIndex = index
  }

  func updateSelection(_ text: String?) {
    selectedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func addStroke(_ stroke: InkStroke) {
    strokes.append(stroke)
    sidecar?.strokes = strokes
    sidecar?.updatedAt = Date()
    statusMessage = "保存済み"
    saveSidecar()
  }

  func removeStroke(id: UUID) {
    guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
    strokes.remove(at: index)
    statusMessage = "線を取り消しました"
    persistStrokes()
  }

  func restoreStroke(_ stroke: InkStroke) {
    guard !strokes.contains(where: { $0.id == stroke.id }) else { return }
    strokes.append(stroke)
    statusMessage = "線をやり直しました"
    persistStrokes()
  }

  var selectedStickyNote: StickyNote? {
    guard let selectedStickyNoteID else { return nil }
    return stickyNotes.first { $0.id == selectedStickyNoteID }
  }

  func stickyNotes(for pageIndex: Int) -> [StickyNote] {
    stickyNotes.filter { $0.pageIndex == pageIndex }
  }

  func selectStickyNote(id: UUID?) {
    guard id == nil || stickyNotes.contains(where: { $0.id == id }) else { return }
    selectedStickyNoteID = id
  }

  func navigateToStickyNote(_ note: StickyNote) {
    guard stickyNotes.contains(where: { $0.id == note.id }),
      note.pageIndex >= 0,
      note.pageIndex < pageCount
    else { return }
    // This is an explicit user navigation, so it supersedes any pending
    // best-effort restoration notification from initial document loading.
    restoreTargetPageIndex = nil
    selectedStickyNoteID = note.id
    goToPageAction?(note.pageIndex)
    statusMessage = "\(note.pageIndex + 1)ページ目の付箋へ移動しました"
  }

  func addStickyNote(_ note: StickyNote) {
    guard !stickyNotes.contains(where: { $0.id == note.id }) else { return }
    stickyNotes.append(note)
    selectedStickyNoteID = note.id
    statusMessage = "保存済み"
    persistStickyNotes()
  }

  func removeStickyNote(id: UUID) {
    guard stickyNotes.contains(where: { $0.id == id }) else { return }
    stickyNotes.removeAll { $0.id == id }
    if selectedStickyNoteID == id {
      selectedStickyNoteID = nil
    }
    statusMessage = "付箋を削除しました"
    persistStickyNotes()
  }

  func restoreStickyNote(_ note: StickyNote) {
    guard !stickyNotes.contains(where: { $0.id == note.id }) else { return }
    stickyNotes.append(note)
    selectedStickyNoteID = note.id
    statusMessage = "付箋を復元しました"
    persistStickyNotes()
  }

  func updateSelectedStickyNoteText(_ text: String) {
    guard let id = selectedStickyNoteID,
      let index = stickyNotes.firstIndex(where: { $0.id == id })
    else { return }
    stickyNotes[index].text = String(text.prefix(500))
    stickyNotes[index].updatedAt = Date()
    persistStickyNotes()
  }

  func deleteSelectedStickyNote(registeringWith undoManager: UndoManager?) {
    guard let note = selectedStickyNote else { return }
    removeStickyNote(id: note.id)
    guard let undoManager else { return }
    registerStickyPresenceChange(note, shouldExist: true, with: undoManager)
    undoManager.setActionName("付箋を削除")
  }

  private func registerStickyPresenceChange(
    _ note: StickyNote,
    shouldExist: Bool,
    with undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: self) { [weak undoManager] model in
      if shouldExist {
        model.restoreStickyNote(note)
      } else {
        model.removeStickyNote(id: note.id)
      }
      guard let undoManager else { return }
      model.registerStickyPresenceChange(
        note,
        shouldExist: !shouldExist,
        with: undoManager
      )
      undoManager.setActionName("付箋を削除")
    }
  }

  func reportAnnotationNotPermitted() {
    statusMessage = "このPDFには線や付箋を追加できません"
  }

  func noteText(for pageIndex: Int) -> String {
    pageNotes[pageIndex]?.text ?? ""
  }

  func setNoteText(_ text: String, for pageIndex: Int) {
    pageNotes[pageIndex] = PageNote(pageIndex: pageIndex, text: text)
    sidecar?.pageNotes = pageNotes
    sidecar?.updatedAt = Date()
    saveSidecar()
  }

  func appendSelectionToCurrentNote() {
    guard permissions.allowsCopying else {
      statusMessage = "このPDFはテキストのコピーを許可していません"
      return
    }
    guard !selectedText.isEmpty else { return }

    let existing = noteText(for: currentPageIndex)
    let quote =
      selectedText
      .split(whereSeparator: \Character.isNewline)
      .map(String.init)
      .joined(separator: " ")
    let addition = "> \(quote)"
    let updated = existing.isEmpty ? addition : "\(existing)\n\n\(addition)"
    statusMessage = "選択テキストをページメモへ追加しました"
    setNoteText(updated, for: currentPageIndex)
  }

  func copySelection() {
    guard permissions.allowsCopying else {
      statusMessage = "このPDFはテキストのコピーを許可していません"
      return
    }
    guard !selectedText.isEmpty else {
      statusMessage = "コピーするテキストを選択してください"
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(selectedText, forType: .string)
    statusMessage = "選択テキストをコピーしました"
  }

  private func persistStrokes() {
    sidecar?.strokes = strokes
    sidecar?.updatedAt = Date()
    saveSidecar()
  }

  private func rememberSuccessfulOpen(_ url: URL) {
    // Bookmark persistence is a convenience feature. Failure must not undo a
    // PDF that is already open and usable.
    try? recentPDFStore.recordSuccessfulOpen(url)
    recentPDFs = recentPDFStore.resolvedEntries()
  }

  private func persistStickyNotes() {
    sidecar?.stickyNotes = stickyNotes
    sidecar?.updatedAt = Date()
    saveSidecar()
  }

  private func saveSidecar() {
    guard var sidecar, let sidecarURL else { return }
    sidecar.sourceFilename = documentURL?.lastPathComponent ?? sidecar.sourceFilename
    sidecar.strokes = strokes
    sidecar.stickyNotes = stickyNotes
    sidecar.pageNotes = pageNotes
    sidecar.pageVisits = pageVisits
    sidecar.lastPageIndex = currentPageIndex
    sidecar.updatedAt = Date()
    self.sidecar = sidecar

    do {
      try store.save(sidecar, to: sidecarURL)
    } catch {
      statusMessage = "線やメモを保存できませんでした: \(error.localizedDescription)"
    }
  }
}
