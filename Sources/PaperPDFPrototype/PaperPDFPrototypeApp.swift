import PaperPDFCore
import SwiftUI

struct OpenPDFActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

struct RecentPDFCommandContext {
  var entries: [ResolvedRecentPDF]
  var open: (UUID) -> Void
  var clear: () -> Void
}

struct RecentPDFCommandContextKey: FocusedValueKey {
  typealias Value = RecentPDFCommandContext
}

extension FocusedValues {
  var openPDFAction: (() -> Void)? {
    get { self[OpenPDFActionKey.self] }
    set { self[OpenPDFActionKey.self] = newValue }
  }

  var recentPDFCommandContext: RecentPDFCommandContext? {
    get { self[RecentPDFCommandContextKey.self] }
    set { self[RecentPDFCommandContextKey.self] = newValue }
  }
}

struct ReaderCommands: Commands {
  @FocusedValue(\.openPDFAction) private var openPDF
  @FocusedValue(\.recentPDFCommandContext) private var recentPDFs

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("PDFを開く…") {
        openPDF?()
      }
      .keyboardShortcut("o", modifiers: [.command])
      .disabled(openPDF == nil)

      Menu("最近開いたPDF") {
        if let recentPDFs, !recentPDFs.entries.isEmpty {
          ForEach(recentPDFs.entries) { entry in
            Button(entry.displayName) {
              recentPDFs.open(entry.id)
            }
            .help(entry.pathHint)
          }
        } else {
          Button("履歴はありません") {}
            .disabled(true)
        }

        Divider()
        Button("履歴を消去") {
          recentPDFs?.clear()
        }
        .disabled(recentPDFs?.entries.isEmpty ?? true)
      }
    }
  }
}

@main
struct PaperPDFPrototypeApp: App {
  var body: some Scene {
    WindowGroup("Paper PDF Prototype") {
      ContentView()
        .frame(minWidth: 980, minHeight: 680)
    }
    .defaultSize(width: 1220, height: 820)
    .commands {
      ReaderCommands()
    }
  }
}
