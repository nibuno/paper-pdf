import AppKit
import PaperPDFCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(\.undoManager) private var undoManager
  @StateObject private var model = ReaderModel()

  var body: some View {
    VStack(spacing: 0) {
      controlBar
      Divider()

      if model.document == nil {
        emptyState
      } else {
        HSplitView {
          HStack(spacing: 0) {
            PDFReaderView(model: model)
              .frame(minWidth: 548)
            if !model.stickyNotes.isEmpty {
              stickyNoteRail
            }
          }
          .frame(minWidth: 620)
          notesPanel
            .frame(minWidth: 280, idealWidth: 330, maxWidth: 440)
        }
      }

      Divider()
      statusBar
    }
    .onOpenURL { model.handleOpenURL($0) }
    .onAppear { model.openCommandLineDocumentIfNeeded() }
    .focusedSceneValue(\.openPDFAction) {
      choosePDF()
    }
    .focusedSceneValue(\.recentPDFCommandContext, recentPDFCommandContext)
  }

  private var controlBar: some View {
    HStack(spacing: 12) {
      Picker("ツール", selection: $model.interactionMode) {
        ForEach(InteractionMode.allCases) { mode in
          Label(mode.rawValue, systemImage: mode.symbolName)
            .tag(mode)
            .help(mode.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 400)
      .disabled(model.document == nil)

      if model.interactionMode.allowsColorSelection {
        ColorPicker(
          "色",
          selection: drawingColorBinding,
          supportsOpacity: false
        )
        .fixedSize()
        .disabled(model.document == nil)
        .help("鉛筆とペンの色を選びます")
      } else if model.interactionMode == .highlighter {
        Label("黄色固定", systemImage: "circle.fill")
          .font(.caption)
          .foregroundStyle(Color.yellow)
          .help("蛍光ペンは読み返しやすい黄色に固定しています")
      }

      HStack(spacing: 3) {
        Button {
          undoManager?.undo()
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("取り消す")
        .help("1つ前の操作に戻ります（Command-Z）")

        Button {
          undoManager?.redo()
        } label: {
          Image(systemName: "arrow.uturn.forward")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("やり直す")
        .help("取り消した操作を1つ先へ進めます（Shift-Command-Z）")
      }
      .disabled(model.document == nil)

      Picker("表示", selection: $model.readingLayout) {
        ForEach(ReadingLayout.allCases) { layout in
          Text(layout.label).tag(layout)
        }
      }
      .frame(width: 145)
      .disabled(model.document == nil)
      .help("連続スクロール、1ページ送り、見開きを切り替えます")

      zoomControls
        .disabled(model.document == nil)

      Spacer()

      if model.pageCount > 0 {
        Text("\(model.currentPageIndex + 1) / \(model.pageCount)ページ")
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var emptyState: some View {
    VStack(spacing: 18) {
      Image(systemName: "book.pages")
        .font(.system(size: 42, weight: .light))
        .foregroundStyle(.secondary)
      VStack(spacing: 6) {
        Text("読む本を選ぶ")
          .font(.title2)
        Text("線やメモは自動で保存されます。元のPDFファイルは変更しません。")
          .foregroundStyle(.secondary)
      }

      if let latest = model.recentPDFs.first {
        VStack(spacing: 14) {
          Text("前回の続き")
            .font(.caption)
            .foregroundStyle(.secondary)

          VStack(spacing: 4) {
            Text(latest.displayName)
              .font(.headline)
              .lineLimit(2)
              .multilineTextAlignment(.center)
            Text(recentPDFDetail(latest))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Button("これを読む") {
            model.openRecentPDF(id: latest.id)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .accessibilityHint("前回開いていたPDFを開きます")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: 480)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        if model.recentPDFs.count > 1 {
          VStack(alignment: .leading, spacing: 6) {
            Text("ほかの最近開いたPDF")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)

            ForEach(Array(model.recentPDFs.dropFirst())) { entry in
              recentPDFButton(entry)
            }
          }
          .frame(maxWidth: 480)
        }

        Button("別のPDFを選ぶ…") {
          choosePDF()
        }
      } else {
        Button("PDFを選ぶ") {
          choosePDF()
        }
        .controlSize(.large)
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func recentPDFButton(_ entry: ResolvedRecentPDF) -> some View {
    Button {
      model.openRecentPDF(id: entry.id)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "doc.richtext")
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.displayName)
            .lineLimit(1)
          Text(recentPDFDetail(entry))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .accessibilityLabel("最近開いたPDF、\(entry.displayName)、\(recentPDFDetail(entry))")
    .help("\(entry.displayName)を開く")
  }

  private var recentPDFCommandContext: RecentPDFCommandContext {
    let readerModel = model
    return RecentPDFCommandContext(
      entries: model.recentPDFs,
      open: { [weak readerModel] id in readerModel?.openRecentPDF(id: id) },
      clear: { [weak readerModel] in readerModel?.clearRecentPDFs() }
    )
  }

  private func recentPDFDetail(_ entry: ResolvedRecentPDF) -> String {
    let date = entry.lastOpenedAt.formatted(
      date: .abbreviated,
      time: .shortened
    )
    return "\(entry.pathHint) ・ \(date)"
  }

  private func choosePDF() {
    NSApplication.shared.activate(ignoringOtherApps: true)

    let panel = NSOpenPanel()
    panel.title = "技術書PDFを開く"
    panel.prompt = "開く"
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false

    if panel.runModal() == .OK, let url = panel.url {
      model.openDocument(at: url)
    }
  }

  private var notesPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("ページメモ")
          .font(.headline)
        Text("\(model.currentPageIndex + 1)ページ目")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      TextEditor(
        text: Binding(
          get: { model.noteText(for: model.currentPageIndex) },
          set: { model.setNoteText($0, for: model.currentPageIndex) }
        )
      )
      .font(.body)
      .scrollContentBackground(.hidden)
      .padding(8)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color(nsColor: .separatorColor))
      }
      .frame(minHeight: 130)

      Divider()

      stickyNotesSection

      VStack(alignment: .leading, spacing: 8) {
        Text("選択テキスト")
          .font(.headline)

        if model.selectedText.isEmpty {
          Text("PDF本文をドラッグして、引用したい部分を選択してください。")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(model.selectedText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
        }

        if !model.permissions.allowsCopying {
          Label(
            "このPDFはコピー不許可のため、本文のコピーとメモ引用は利用できません。ページメモは手入力できます。",
            systemImage: "lock.fill"
          )
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
          Button("コピー") {
            model.copySelection()
          }
          Button("選択部分をメモへ追加") {
            model.appendSelectionToCurrentNote()
          }
        }
        .disabled(model.selectedText.isEmpty || !model.permissions.allowsCopying)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var stickyNotesSection: some View {
    let notes = model.stickyNotes(for: model.currentPageIndex)
    let selected = model.selectedStickyNote.flatMap { note in
      note.pageIndex == model.currentPageIndex ? note : nil
    }

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("付箋", systemImage: "note.text")
          .font(.headline)
        Spacer()
        Text("このページ: \(notes.count)枚")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if notes.isEmpty {
        Text("上の付箋ツールを選び、ページ上の残したい場所をクリックします。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Picker(
          "編集する付箋",
          selection: Binding<UUID?>(
            get: { selected?.id },
            set: { model.selectStickyNote(id: $0) }
          )
        ) {
          Text("付箋を選択").tag(nil as UUID?)
          ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
            Text(stickyNoteLabel(note, number: index + 1))
              .tag(Optional(note.id))
          }
        }

        if selected != nil {
          TextEditor(
            text: Binding(
              get: { model.selectedStickyNote?.text ?? "" },
              set: { model.updateSelectedStickyNoteText($0) }
            )
          )
          .font(.body)
          .frame(height: 82)
          .scrollContentBackground(.hidden)
          .padding(6)
          .background(Color.yellow.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 5))
          .overlay {
            RoundedRectangle(cornerRadius: 5)
              .stroke(Color.orange.opacity(0.55))
          }
          .disabled(!model.permissions.allowsCommenting)

          HStack {
            Text("500文字まで")
              .font(.caption2)
              .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
              model.deleteSelectedStickyNote(registeringWith: undoManager)
            } label: {
              Label("削除", systemImage: "trash")
            }
            .disabled(!model.permissions.allowsCommenting)
          }
        }
      }
    }
  }

  private var stickyNoteRail: some View {
    VStack(spacing: 0) {
      VStack(spacing: 2) {
        Image(systemName: "note.text")
          .font(.caption)
        Text("\(model.stickyNotes.count)")
          .font(.system(.caption2, design: .monospaced))
      }
      .foregroundStyle(.white.opacity(0.62))
      .padding(.vertical, 8)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("付箋一覧、\(model.stickyNotes.count)枚")

      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(Array(sortedStickyNotes.enumerated()), id: \.element.id) { index, note in
            stickyTab(for: note, number: index + 1)
          }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.hidden)
    }
    .frame(width: 72)
    .background(Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1)))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color.white.opacity(0.08))
        .frame(width: 1)
    }
  }

  private var sortedStickyNotes: [StickyNote] {
    model.stickyNotes.sorted { lhs, rhs in
      if lhs.pageIndex != rhs.pageIndex {
        return lhs.pageIndex < rhs.pageIndex
      }
      if lhs.position.y != rhs.position.y {
        // PDF coordinates grow upward; higher anchors come first on a page.
        return lhs.position.y > rhs.position.y
      }
      return lhs.createdAt < rhs.createdAt
    }
  }

  private func stickyTab(for note: StickyNote, number: Int) -> some View {
    let isSelected = note.id == model.selectedStickyNoteID
    let isCurrentPage = note.pageIndex == model.currentPageIndex
    let snippet = stickyTabSnippet(note, number: number)
    let tabWidth: CGFloat = isSelected ? 66 : (isCurrentPage ? 62 : 56)

    return Button {
      model.navigateToStickyNote(note)
    } label: {
      VStack(alignment: .leading, spacing: 1) {
        Text("p.\(note.pageIndex + 1)")
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
        Text(snippet)
          .font(.system(size: 9))
          .lineLimit(1)
      }
      .foregroundStyle(Color.black.opacity(0.72))
      .padding(.horizontal, 7)
      .frame(width: tabWidth, height: isSelected ? 42 : 35, alignment: .leading)
      .background(stickyTabColor(isSelected: isSelected, isCurrentPage: isCurrentPage))
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(
            isSelected ? Color.orange.opacity(0.9) : Color.white.opacity(isCurrentPage ? 0.36 : 0),
            lineWidth: isSelected ? 2 : 1
          )
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel("\(note.pageIndex + 1)ページの付箋、\(snippet)")
    .help("\(note.pageIndex + 1)ページへ移動: \(snippet)")
  }

  private func stickyTabSnippet(_ note: StickyNote, number: Int) -> String {
    let text = note.text
      .split(whereSeparator: \Character.isNewline)
      .map(String.init)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "付箋 \(number)" : String(text.prefix(16))
  }

  private func stickyTabColor(isSelected: Bool, isCurrentPage: Bool) -> Color {
    if isSelected {
      return Color(red: 1, green: 0.78, blue: 0.16)
    }
    if isCurrentPage {
      return Color(red: 1, green: 0.84, blue: 0.25).opacity(0.94)
    }
    return Color(red: 0.96, green: 0.76, blue: 0.22).opacity(0.78)
  }

  private func stickyNoteLabel(_ note: StickyNote, number: Int) -> String {
    let oneLine = note.text
      .split(whereSeparator: \Character.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return oneLine.isEmpty ? "付箋 \(number)" : oneLine
  }

  private var drawingColorBinding: Binding<Color> {
    Binding(
      get: {
        Color(
          red: model.drawingColor.red,
          green: model.drawingColor.green,
          blue: model.drawingColor.blue
        )
      },
      set: { color in
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
        model.drawingColor = StrokeColor(
          red: Double(rgb.redComponent),
          green: Double(rgb.greenComponent),
          blue: Double(rgb.blueComponent)
        )
      }
    )
  }

  private var zoomControls: some View {
    HStack(spacing: 3) {
      Button {
        model.zoomOut()
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("縮小")
      .help("縮小")

      Menu {
        Button("画面に合わせる") {
          model.fitToView()
        }
        Button("実寸（100%）") {
          model.setZoomScale(1)
        }
        Divider()
        ForEach([0.5, 0.75, 1.25, 1.5, 2.0], id: \.self) { scale in
          Button("\(Int(scale * 100))%") {
            model.setZoomScale(scale)
          }
        }
      } label: {
        Text("\(Int((model.zoomScaleFactor * 100).rounded()))%")
          .font(.system(.caption, design: .monospaced))
          .frame(minWidth: 44)
      }
      .menuStyle(.borderlessButton)
      .help("倍率を選択")

      Button {
        model.zoomIn()
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("拡大")
      .help("拡大")
    }
  }

  private var statusBar: some View {
    HStack {
      Text(model.statusMessage)
        .lineLimit(1)
      Spacer()
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }
}
