import AppKit
import PDFKit
import PaperPDFCore
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
  @ObservedObject var model: ReaderModel

  func makeCoordinator() -> Coordinator {
    Coordinator(model: model)
  }

  func makeNSView(context: Context) -> PencilPDFView {
    let view = PencilPDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.displaysPageBreaks = true
    view.pageShadowsEnabled = true
    view.minScaleFactor = 0.25
    view.maxScaleFactor = 5
    view.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
    view.pageOverlayViewProvider = view
    context.coordinator.attach(to: view)
    return view
  }

  func updateNSView(_ view: PencilPDFView, context: Context) {
    view.isApplyingRepresentableUpdate = true
    defer {
      view.isApplyingRepresentableUpdate = false
      view.isApplyingPreferredLayoutAnchor = false
    }

    if view.document !== model.document {
      let restorePageIndex = model.currentPageIndex
      model.beginRestoringPage(to: restorePageIndex)
      view.prepareForDocumentChange()
      view.document = model.document
      view.sync(strokes: model.strokes)
      view.sync(stickyNotes: model.stickyNotes)

      if let document = model.document,
        let page = document.page(at: restorePageIndex)
      {
        view.go(to: page)
      }
    } else {
      view.sync(strokes: model.strokes)
      view.sync(stickyNotes: model.stickyNotes)
    }

    view.syncPaperWear(
      pageVisits: model.pageVisits,
      fingerprint: model.documentFingerprint
    )
    view.interactionMode = model.interactionMode
    view.drawingColor = model.activeDrawingColor
    view.apply(
      readingLayout: model.readingLayout,
      preferredStickyNote: model.selectedStickyNote
    )
  }

  @MainActor
  final class Coordinator: NSObject {
    private let model: ReaderModel
    private weak var view: PencilPDFView?

    init(model: ReaderModel) {
      self.model = model
      super.init()
    }

    func attach(to view: PencilPDFView) {
      self.view = view
      view.onStrokeFinished = { [weak self] stroke in
        self?.model.addStroke(stroke)
      }
      view.onStrokeRemovalRequested = { [weak self] id in
        self?.model.removeStroke(id: id)
      }
      view.onStrokeRestoreRequested = { [weak self] stroke in
        self?.model.restoreStroke(stroke)
      }
      view.onStickyNotePlaced = { [weak self] note in
        self?.model.addStickyNote(note)
      }
      view.onStickyNoteRemovalRequested = { [weak self] id in
        self?.model.removeStickyNote(id: id)
      }
      view.onStickyNoteRestoreRequested = { [weak self] note in
        self?.model.restoreStickyNote(note)
      }
      view.onStickyNoteSelected = { [weak self] id in
        self?.model.selectStickyNote(id: id)
      }
      view.onLayoutAnchorApplied = { [weak self, weak view] noteID, pageIndex in
        DispatchQueue.main.async { [weak self, weak view] in
          guard let self, let view,
            view.document === self.model.document,
            self.model.selectedStickyNoteID == noteID,
            self.model.selectedStickyNote?.pageIndex == pageIndex
          else { return }
          self.model.setCurrentPage(pageIndex)
        }
      }
      view.onSelectionChanged = { [weak self] text in
        self?.model.updateSelection(text)
      }
      view.onAnnotationPermissionDenied = { [weak self] in
        self?.model.reportAnnotationNotPermitted()
      }
      model.configureZoomActions(
        zoomIn: { [weak view] in view?.zoomInStep() },
        zoomOut: { [weak view] in view?.zoomOutStep() },
        fitToView: { [weak view] in view?.fitToView() },
        setZoom: { [weak view] scale in view?.setZoomScale(scale) }
      )
      model.configurePageNavigation { [weak self, weak view] pageIndex in
        guard let self, let view else { return }
        view.goToPage(at: pageIndex)
        // PDFKit can keep the same currentPage when the target is the other
        // half of an already visible spread. Use the normal model update as a
        // fallback so the matching editor is exposed in two-page mode too.
        self.model.setCurrentPage(pageIndex)
      }

      let center = NotificationCenter.default
      center.addObserver(
        self,
        selector: #selector(pageDidChange(_:)),
        name: .PDFViewPageChanged,
        object: view
      )
      center.addObserver(
        self,
        selector: #selector(selectionDidChange(_:)),
        name: .PDFViewSelectionChanged,
        object: view
      )
      center.addObserver(
        self,
        selector: #selector(scaleDidChange(_:)),
        name: .PDFViewScaleChanged,
        object: view
      )
    }

    @objc private func pageDidChange(_ notification: Notification) {
      guard let view,
        let document = view.document,
        let page = view.currentPage
      else { return }
      let pageIndex = document.index(for: page)
      guard view.isApplyingRepresentableUpdate else {
        model.setCurrentPage(pageIndex)
        return
      }
      // A selected sticky note has an explicit deferred synchronization below;
      // ignore PDFKit's intermediate left-page notifications while rebuilding
      // a two-page spread.
      guard !view.isApplyingPreferredLayoutAnchor else { return }

      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let view,
          view.document === self.model.document,
          let currentPage = view.currentPage,
          view.document?.index(for: currentPage) == pageIndex
        else { return }
        self.model.setCurrentPage(pageIndex)
      }
    }

    @objc private func selectionDidChange(_ notification: Notification) {
      model.updateSelection(view?.currentSelection?.string)
    }

    @objc private func scaleDidChange(_ notification: Notification) {
      guard let view else { return }
      let scale = view.scaleFactor
      guard view.isApplyingRepresentableUpdate else {
        model.updateZoomScale(scale)
        return
      }

      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let view,
          view.document === self.model.document,
          abs(view.scaleFactor - scale) < 0.0001
        else { return }
        self.model.updateZoomScale(scale)
      }
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}

@MainActor
final class PencilPDFView: PDFView, @preconcurrency PDFPageOverlayViewProvider {
  var interactionMode: InteractionMode = .reading
  var drawingColor = StrokeColor.graphite
  var onStrokeFinished: ((InkStroke) -> Void)?
  var onStrokeRemovalRequested: ((UUID) -> Void)?
  var onStrokeRestoreRequested: ((InkStroke) -> Void)?
  var onStickyNotePlaced: ((StickyNote) -> Void)?
  var onStickyNoteRemovalRequested: ((UUID) -> Void)?
  var onStickyNoteRestoreRequested: ((StickyNote) -> Void)?
  var onStickyNoteSelected: ((UUID?) -> Void)?
  var onLayoutAnchorApplied: ((UUID, Int) -> Void)?
  var onSelectionChanged: ((String?) -> Void)?
  var onAnnotationPermissionDenied: (() -> Void)?
  var isApplyingRepresentableUpdate = false
  var isApplyingPreferredLayoutAnchor = false

  private var activePage: PDFPage?
  private var activePageIndex: Int?
  private var activePoints: [CGPoint] = []
  private var transientAnnotation: PDFAnnotation?
  private var renderedAnnotations: [UUID: PDFAnnotation] = [:]
  private var storedStrokes: [InkStroke] = []
  private var storedStickyNotes: [StickyNote] = []
  private var storedPageVisits: [Int: Int] = [:]
  private var documentFingerprint = ""
  private var paperOverlays: [ObjectIdentifier: PaperWearOverlayView] = [:]
  private var erasedStrokeIDsDuringGesture: Set<UUID> = []
  private var readingLayout: ReadingLayout = .continuous
  private var scrollDelta: CGFloat = 0
  private var didTurnPageDuringGesture = false
  private var lastWheelPageTurnAt: TimeInterval = 0

  func zoomInStep() {
    autoScales = false
    zoomIn(nil)
  }

  func zoomOutStep() {
    autoScales = false
    zoomOut(nil)
  }

  func fitToView() {
    autoScales = true
    scaleFactor = scaleFactorForSizeToFit
  }

  func setZoomScale(_ scale: CGFloat) {
    autoScales = false
    scaleFactor = min(max(scale, minScaleFactor), maxScaleFactor)
  }

  func goToPage(at pageIndex: Int) {
    guard let document,
      pageIndex >= 0,
      pageIndex < document.pageCount,
      let page = document.page(at: pageIndex)
    else { return }
    go(to: page)
    window?.makeFirstResponder(self)
  }

  func apply(readingLayout newLayout: ReadingLayout, preferredStickyNote: StickyNote?) {
    guard readingLayout != newLayout else { return }

    let previousVisiblePage = currentPage
    let preferredAnchor: (noteID: UUID, pageIndex: Int, page: PDFPage)? = {
      guard let preferredStickyNote,
        let document,
        preferredStickyNote.pageIndex >= 0,
        preferredStickyNote.pageIndex < document.pageCount,
        let page = document.page(at: preferredStickyNote.pageIndex)
      else { return nil }
      return (preferredStickyNote.id, preferredStickyNote.pageIndex, page)
    }()
    isApplyingPreferredLayoutAnchor = preferredAnchor != nil
    let anchorPage = preferredAnchor?.page ?? previousVisiblePage
    readingLayout = newLayout
    displaysAsBook = newLayout == .twoPage
    displayMode = switch newLayout {
    case .continuous: .singlePageContinuous
    case .singlePage: .singlePage
    case .twoPage: .twoUp
    }
    if newLayout == .twoPage {
      // PDFKit's default left/right margins and page shadows create a visible
      // gutter between the two pages. Keep only vertical breathing room.
      displaysPageBreaks = true
      pageBreakMargins = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
      pageShadowsEnabled = false
    } else {
      displaysPageBreaks = true
      pageBreakMargins = NSEdgeInsets(top: 4.75, left: 4, bottom: 4.75, right: 4)
      pageShadowsEnabled = true
    }
    displayDirection = .vertical
    autoScales = true
    resetScrollGesture()

    if let anchorPage {
      go(to: anchorPage)
    }
    if let preferredAnchor {
      onLayoutAnchorApplied?(preferredAnchor.noteID, preferredAnchor.pageIndex)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard readingLayout.isPaged else {
      super.scrollWheel(with: event)
      return
    }

    // Momentum after a trackpad gesture must not turn several extra pages.
    guard event.momentumPhase.isEmpty else { return }

    if event.phase.contains(.began) {
      resetScrollGesture()
    }

    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      resetScrollGesture()
      return
    }

    let delta = event.scrollingDeltaY
    guard delta != 0 else { return }

    if event.phase.isEmpty {
      // A mouse wheel has no gesture phases, so rate-limit its individual ticks.
      guard event.timestamp - lastWheelPageTurnAt > 0.28 else { return }
      lastWheelPageTurnAt = event.timestamp
      turnPage(forward: delta < 0)
      return
    }

    scrollDelta += delta
    guard !didTurnPageDuringGesture, abs(scrollDelta) >= 18 else { return }
    didTurnPageDuringGesture = true
    turnPage(forward: scrollDelta < 0)
  }

  override func keyDown(with event: NSEvent) {
    // Only handle unmodified horizontal arrow keys while the PDF view itself
    // owns keyboard focus. A TextEditor in the memo panel receives its own
    // key events, so its caret movement is left untouched.
    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 123:  // Left Arrow
      turnPage(forward: false)
    case 124:  // Right Arrow
      turnPage(forward: true)
    default:
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    let viewPoint = convert(event.locationInWindow, from: nil)
    let pointedPage = page(for: viewPoint, nearest: false)

    guard interactionMode.editsAnnotations,
      let document,
      !document.isLocked
    else {
      if interactionMode == .reading {
        onStickyNoteSelected?(nil)
      }
      super.mouseDown(with: event)
      return
    }
    guard document.allowsCommenting else {
      onAnnotationPermissionDenied?()
      return
    }

    window?.makeFirstResponder(self)

    guard let page = pointedPage else { return }

    if interactionMode == .stickyNote {
      let note = makeStickyNote(at: convert(viewPoint, to: page), on: page)
      onStickyNotePlaced?(note)
      onStickyNoteSelected?(note.id)
      registerUndoForStickyPlacement(note)
      return
    }

    if interactionMode == .eraser {
      erasedStrokeIDsDuringGesture.removeAll()
      eraseStroke(near: convert(viewPoint, to: page), on: page)
      return
    }

    activePage = page
    activePageIndex = document.index(for: page)
    activePoints = [convert(viewPoint, to: page)]
  }

  override func mouseDragged(with event: NSEvent) {
    if interactionMode == .stickyNote {
      return
    }

    if interactionMode == .eraser {
      let viewPoint = convert(event.locationInWindow, from: nil)
      guard let page = page(for: viewPoint, nearest: false) else { return }
      eraseStroke(near: convert(viewPoint, to: page), on: page)
      return
    }

    guard interactionMode.isDrawing,
      let page = activePage
    else {
      super.mouseDragged(with: event)
      return
    }

    let viewPoint = convert(event.locationInWindow, from: nil)
    guard self.page(for: viewPoint, nearest: false) === page else { return }

    let point = convert(viewPoint, to: page)
    if event.modifierFlags.contains(.shift), let start = activePoints.first {
      activePoints = [start, point]
    } else {
      activePoints.append(point)
    }
    updateTransientAnnotation(on: page)
  }

  override func mouseUp(with event: NSEvent) {
    if interactionMode == .stickyNote {
      return
    }

    if interactionMode == .eraser {
      erasedStrokeIDsDuringGesture.removeAll()
      return
    }

    guard interactionMode.isDrawing,
      let page = activePage,
      let pageIndex = activePageIndex
    else {
      super.mouseUp(with: event)
      publishSelectionAfterPDFKitFinishes()
      return
    }

    if let transientAnnotation {
      page.removeAnnotation(transientAnnotation)
    }

    if activePoints.count >= 2,
      let kind = interactionMode.strokeKind
    {
      let stroke = InkStroke(
        pageIndex: pageIndex,
        points: activePoints.map { PDFPoint(x: Double($0.x), y: Double($0.y)) },
        lineWidth: interactionMode.lineWidth,
        kind: kind,
        color: drawingColor
      )
      onStrokeFinished?(stroke)
      registerUndo(for: stroke)
    }

    activePage = nil
    activePageIndex = nil
    activePoints = []
    transientAnnotation = nil
  }

  private func publishSelectionAfterPDFKitFinishes() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.onSelectionChanged?(self.currentSelection?.string)
    }
  }

  private func turnPage(forward: Bool) {
    guard let document, let currentPage else { return }
    let currentIndex = document.index(for: currentPage)
    let targetIndex: Int

    switch readingLayout {
    case .continuous, .singlePage:
      targetIndex = currentIndex + (forward ? 1 : -1)
    case .twoPage:
      let spreadStart: Int
      if currentIndex == 0 {
        spreadStart = 0
      } else {
        spreadStart = currentIndex.isMultiple(of: 2) ? currentIndex - 1 : currentIndex
      }
      if forward {
        targetIndex = spreadStart == 0 ? 1 : spreadStart + 2
      } else {
        targetIndex = spreadStart <= 1 ? 0 : spreadStart - 2
      }
    }

    guard targetIndex >= 0,
      targetIndex < document.pageCount,
      let targetPage = document.page(at: targetIndex)
    else { return }
    go(to: targetPage)
  }

  private func resetScrollGesture() {
    scrollDelta = 0
    didTurnPageDuringGesture = false
  }

  func prepareForDocumentChange() {
    // The window undo manager also contains sticky-note deletion actions whose
    // target is ReaderModel. Clear the whole document history so an action from
    // the previous PDF can never mutate the newly opened sidecar.
    undoManager?.removeAllActions()
    for annotation in renderedAnnotations.values {
      annotation.page?.removeAnnotation(annotation)
    }
    renderedAnnotations.removeAll()
    storedStrokes = []
    storedStickyNotes = []
    storedPageVisits = [:]
    documentFingerprint = ""
    paperOverlays.removeAll()
    erasedStrokeIDsDuringGesture.removeAll()
    transientAnnotation = nil
    activePoints = []
  }

  func sync(strokes: [InkStroke]) {
    storedStrokes = strokes
    let desiredIDs = Set(strokes.map(\.id))
    let removedIDs = renderedAnnotations.keys.filter { !desiredIDs.contains($0) }

    for id in removedIDs {
      guard let annotation = renderedAnnotations[id] else { continue }
      annotation.page?.removeAnnotation(annotation)
      renderedAnnotations.removeValue(forKey: id)
    }

    for stroke in strokes where renderedAnnotations[stroke.id] == nil {
      guard let page = document?.page(at: stroke.pageIndex),
        let annotation = makeAnnotation(for: stroke)
      else { continue }
      page.addAnnotation(annotation)
      renderedAnnotations[stroke.id] = annotation
    }
  }

  func sync(stickyNotes: [StickyNote]) {
    storedStickyNotes = stickyNotes
  }

  func syncPaperWear(pageVisits: [Int: Int], fingerprint: String) {
    guard storedPageVisits != pageVisits || documentFingerprint != fingerprint else { return }
    storedPageVisits = pageVisits
    documentFingerprint = fingerprint

    for overlay in paperOverlays.values {
      overlay.update(
        visitCount: pageVisits[overlay.pageIndex, default: 0],
        textureSeed: PaperWearOverlayView.stableSeed(
          fingerprint: fingerprint,
          pageIndex: overlay.pageIndex
        )
      )
    }
  }

  func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
    guard let document else { return nil }
    let pageIndex = document.index(for: page)
    guard pageIndex >= 0 else { return nil }

    let identifier = ObjectIdentifier(page)
    if let existing = paperOverlays[identifier] {
      return existing
    }

    let overlay = PaperWearOverlayView(
      pageIndex: pageIndex,
      visitCount: storedPageVisits[pageIndex, default: 0],
      textureSeed: PaperWearOverlayView.stableSeed(
        fingerprint: documentFingerprint,
        pageIndex: pageIndex
      )
    )
    paperOverlays[identifier] = overlay
    return overlay
  }

  private func makeStickyNote(at point: CGPoint, on page: PDFPage) -> StickyNote {
    let pageBounds = page.bounds(for: .cropBox)
    let position = CGPoint(
      x: min(max(point.x, pageBounds.minX), pageBounds.maxX),
      y: min(max(point.y, pageBounds.minY), pageBounds.maxY)
    )
    return StickyNote(
      pageIndex: document?.index(for: page) ?? 0,
      position: PDFPoint(x: Double(position.x), y: Double(position.y))
    )
  }

  private func updateTransientAnnotation(on page: PDFPage) {
    if let transientAnnotation {
      page.removeAnnotation(transientAnnotation)
    }

    guard let kind = interactionMode.strokeKind else { return }
    let stroke = InkStroke(
      pageIndex: activePageIndex ?? 0,
      points: activePoints.map { PDFPoint(x: Double($0.x), y: Double($0.y)) },
      lineWidth: interactionMode.lineWidth,
      kind: kind,
      color: drawingColor
    )
    transientAnnotation = makeAnnotation(for: stroke)
    if let transientAnnotation {
      page.addAnnotation(transientAnnotation)
    }
  }

  private func eraseStroke(near point: CGPoint, on page: PDFPage) {
    guard let document else { return }
    let pageIndex = document.index(for: page)
    let viewTolerance = 7 / max(scaleFactor, 0.25)

    let candidate = storedStrokes
      .enumerated()
      .filter { _, stroke in
        stroke.pageIndex == pageIndex
          && !erasedStrokeIDsDuringGesture.contains(stroke.id)
          && stroke.points.count >= 2
      }
      .compactMap { index, stroke -> (Int, InkStroke, CGFloat)? in
        let distance = distance(from: point, to: stroke)
        let tolerance = max(CGFloat(stroke.lineWidth) / 2 + viewTolerance, viewTolerance)
        return distance <= tolerance ? (index, stroke, distance) : nil
      }
      .min { lhs, rhs in
        if abs(lhs.2 - rhs.2) < 0.5 {
          return lhs.0 > rhs.0
        }
        return lhs.2 < rhs.2
      }

    guard let (_, stroke, _) = candidate else { return }
    erasedStrokeIDsDuringGesture.insert(stroke.id)
    storedStrokes.removeAll { $0.id == stroke.id }
    if let annotation = renderedAnnotations.removeValue(forKey: stroke.id) {
      annotation.page?.removeAnnotation(annotation)
    }
    onStrokeRemovalRequested?(stroke.id)
    registerUndoForErase(stroke)
  }

  private func distance(from point: CGPoint, to stroke: InkStroke) -> CGFloat {
    let points = stroke.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    var shortest = CGFloat.greatestFiniteMagnitude
    for (start, end) in zip(points, points.dropFirst()) {
      let segment = end - start
      let lengthSquared = segment.x * segment.x + segment.y * segment.y
      let projection: CGFloat
      if lengthSquared == 0 {
        projection = 0
      } else {
        projection = min(
          max(((point - start).x * segment.x + (point - start).y * segment.y) / lengthSquared, 0),
          1
        )
      }
      let nearest = start + segment * projection
      shortest = min(shortest, hypot(point.x - nearest.x, point.y - nearest.y))
    }
    return shortest
  }

  private func makeAnnotation(for stroke: InkStroke) -> PDFAnnotation? {
    guard stroke.points.count >= 2 else { return nil }

    let points = stroke.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    let minX = points.map(\.x).min() ?? 0
    let maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0
    let maxY = points.map(\.y).max() ?? 0
    let padding = max(CGFloat(stroke.lineWidth) * 2, 3)
    let bounds = CGRect(
      x: minX - padding,
      y: minY - padding,
      width: max(maxX - minX + padding * 2, 1),
      height: max(maxY - minY + padding * 2, 1)
    )

    let path = NSBezierPath()
    path.move(to: CGPoint(x: points[0].x - bounds.minX, y: points[0].y - bounds.minY))
    for point in points.dropFirst() {
      path.line(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
    }

    let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
    let border = PDFBorder()
    border.lineWidth = CGFloat(stroke.lineWidth)
    annotation.border = border
    let storedColor = stroke.color ?? .graphite
    let alpha: CGFloat
    switch stroke.kind ?? .pencil {
    case .pencil: alpha = 0.72
    case .pen: alpha = 0.96
    case .highlighter: alpha = 0.32
    }
    annotation.color = NSColor(
      calibratedRed: CGFloat(storedColor.red),
      green: CGFloat(storedColor.green),
      blue: CGFloat(storedColor.blue),
      alpha: alpha
    )
    annotation.contents = "PaperPDFPrototype:\(stroke.id.uuidString)"
    annotation.add(path)
    return annotation
  }

  private func registerUndo(for stroke: InkStroke) {
    undoManager?.registerUndo(withTarget: self) { view in
      view.undo(stroke: stroke)
    }
    undoManager?.setActionName("線を引く")
  }

  private func registerUndoForErase(_ stroke: InkStroke) {
    undoManager?.registerUndo(withTarget: self) { view in
      view.undoErase(stroke: stroke)
    }
    undoManager?.setActionName("線を消す")
  }

  private func registerUndoForStickyPlacement(_ note: StickyNote) {
    undoManager?.registerUndo(withTarget: self) { view in
      view.undoStickyPlacement(note)
    }
    undoManager?.setActionName("付箋を置く")
  }

  private func undoStickyPlacement(_ note: StickyNote) {
    // Placement undo may happen after the user has entered text. Preserve the
    // latest sidecar snapshot so redo restores that text, not the empty marker
    // originally created on mouse-down.
    let latestNote = storedStickyNotes.first { $0.id == note.id } ?? note
    onStickyNoteRemovalRequested?(latestNote.id)
    undoManager?.registerUndo(withTarget: self) { view in
      view.redoStickyPlacement(latestNote)
    }
    undoManager?.setActionName("付箋を置く")
  }

  private func redoStickyPlacement(_ note: StickyNote) {
    onStickyNoteRestoreRequested?(note)
    undoManager?.registerUndo(withTarget: self) { view in
      view.undoStickyPlacement(note)
    }
    undoManager?.setActionName("付箋を置く")
  }

  private func undoErase(stroke: InkStroke) {
    onStrokeRestoreRequested?(stroke)
    undoManager?.registerUndo(withTarget: self) { view in
      view.redoErase(stroke: stroke)
    }
    undoManager?.setActionName("線を消す")
  }

  private func redoErase(stroke: InkStroke) {
    onStrokeRemovalRequested?(stroke.id)
    undoManager?.registerUndo(withTarget: self) { view in
      view.undoErase(stroke: stroke)
    }
    undoManager?.setActionName("線を消す")
  }

  private func undo(stroke: InkStroke) {
    onStrokeRemovalRequested?(stroke.id)
    undoManager?.registerUndo(withTarget: self) { view in
      view.redo(stroke: stroke)
    }
    undoManager?.setActionName("線を引く")
  }

  private func redo(stroke: InkStroke) {
    onStrokeRestoreRequested?(stroke)
    undoManager?.registerUndo(withTarget: self) { view in
      view.undo(stroke: stroke)
    }
    undoManager?.setActionName("線を引く")
  }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
  CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}
