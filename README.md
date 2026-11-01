# Paper PDF Prototype

技術書PDFをmacOSで読むための、SwiftUI + PDFKit検証アプリです。

線やメモは自動保存され、元のPDFファイルは変更しません。描画、付箋、ページメモ、最終ページ、ページ訪問回数は、PDF内容のSHA-256をキーにした別のデータとして保存します。

## 配布版を使う

初版の配布対象はApple Silicon搭載Mac（M1以降）、macOS 14以降です。GitHub Releasesに公開されたZIPを展開し、`PaperPDFPrototype.app` を「アプリケーション」フォルダに移動してください。Xcodeは不要です。

配布版は簡易署名のみで、Developer ID署名・Appleの公証はありません。初回に警告が出た場合、配布元を確認したうえで「システム設定 → プライバシーとセキュリティ → このまま開く」から、このアプリを許可します。[Appleの起動手順](https://support.apple.com/ja-jp/102445)も参照してください。管理されたMacでは、この操作が制限される場合があります。

アプリ内の自動更新はありません。次の版もReleasesから入手してアプリを入れ替えます。メモはApplication Supportに保存されるので、そのまま引き継がれます。

## 現在の機能

- PDFKitによるPDF表示、テキスト選択・コピー、拡大縮小、ページ移動
- 前回のPDFを「これを読む」で再開できる開始画面と、ファイルメニューから使える最近のPDF（最大5件）
- 連続スクロール・1ページ送り・中央の隙間を抑えた見開き表示の切り替え
- PDF表示にフォーカスがあるときの左右矢印ページ送り（見開きでは見開き単位）
- ピンチ操作とツールバーによる拡大縮小、倍率指定、画面フィット
- PDFの暗号化・ロック・コピー・注釈・文書変更権限の表示
- SF Symbolsで切り替える鉛筆・ペン・黄色固定の蛍光ペン・消しゴム
- 鉛筆とペンの色選択、Shiftを押しながらの直線描画
- サイドカー上の線だけを安全に消す、取り消し可能な消しゴム
- ページ上で位置を決め、紙面外の右端レールに並ぶ黄色い付箋
- 文書内の付箋をページ順に一覧し、クリックで該当ページへ移動・右パネルで編集
- 付箋の配置と削除の取り消し・やり直し
- ツールバーとキーボードによる描画の取り消し・やり直し（Command-Z / Shift-Command-Z）
- ページ単位のメモ
- 選択テキストのメモ引用（コピー許可PDFのみ）
- 最後に読んだページとページ訪問回数の復元
- 再訪したページの紙色・外周・粒子・影が、3段階で少しずつ変わる表示レイヤー
- PDF本体とは別のJSON保存
- PDFが注釈を許可しない場合の描画・付箋入力拒否

サイドカーの通常の保存先は以下です。

```text
~/Library/Application Support/PaperPDFPrototype/Sidecars/
```

`PAPERPDF_SIDECAR_DIR`環境変数で変更できます。

最近のPDFにはmacOSのsecurity-scoped bookmarkを保存します。これは選んだPDFへ再アクセスするための許可証データであり、PDF本体のコピーではありません。履歴はMac内のApplication Supportにだけ保存され、ファイルメニューから消去できます。

## メモのバックアップと引っ越し

書き込みはPDFには入りません。線・付箋・ページメモ・読書位置は、すべて次のフォルダに保存されます。

```text
~/Library/Application Support/PaperPDFPrototype/
```

このフォルダと元のPDFの両方が揃って、はじめて元の状態に戻せます。Time Machineを使っているなら対象に入っていますが、PDFを別の場所（外付けディスクやクラウド）に置いている場合は、そちらもバックアップに含めてください。

別のMacへ移すときは、アプリを入れたうえで、このフォルダをコピーします。

```bash
# 移行元で
ditto ~/Library/Application\ Support/PaperPDFPrototype ~/Desktop/PaperPDFPrototype-backup

# 移行先で（アプリを終了した状態で実行します）
ditto ~/Desktop/PaperPDFPrototype-backup ~/Library/Application\ Support/PaperPDFPrototype
```

サイドカーはPDFの中身のSHA-256で紐づきます。PDFを別のフォルダに移したり名前を変えたりしても、同じファイルなら書き込みは見つかります。逆に、PDFを作り直した場合（別版を買い直した、圧縮し直したなど）は別のPDFとして扱われ、以前の書き込みは表示されません。

アプリを使うのをやめるときは、`PaperPDFPrototype.app` を捨てるだけでは上のフォルダは残ります。書き込みも消すなら、このフォルダごと削除してください。削除すると元に戻せません。

## PDFKit互換性だけを先に確認する

この検証はSwiftツールチェーンに依存せず、現在のmacOS PDFKitを直接呼びます。引数なしの場合は日本語テストPDFを生成して検証します。

```bash
./Scripts/verify-pdfkit.sh
```

所有しているPDFを指定する場合:

```bash
./Scripts/verify-pdfkit.sh "/path/to/購入した技術書.pdf"
```

検証中のインク注釈はメモリ上だけに追加します。PDFファイルへは書き出さず、実行前後で原本バイト列が同一であることも確認します。`allows_commenting=no`ならインクテストはスキップします。

`text_characters=0`の場合は、画像PDFまたはPDFKitがテキスト層を解釈できないPDFです。OCRか座標のみの注釈が必要になります。

## アプリを起動する

ビルド済みの`PaperPDFPrototype.app`をFinderからダブルクリックしてください。ターミナルから再ビルドして起動する場合は次を実行します。

```bash
./Scripts/run.sh
```

最初に開くPDFを指定できます。

```bash
./Scripts/run.sh "/path/to/book.pdf"
```

Xcodeでは`Package.swift`を開き、`PaperPDFPrototype`スキームを実行してください。

## テスト

```bash
./Scripts/test.sh
```

サイドカーの往復保存と旧形式互換、PDF本体が変更されないことに加え、最近のPDFの並び順・重複排除・上限・壊れた履歴の復旧と退避、紙の質感の段階と上限をテストします。スクリプトはSwiftPMとClangのキャッシュをプロジェクト内に保存します。

mainへのpushとプルリクエストでは、`.github/workflows/test.yml` がmacOSのランナーで同じテストとPDFKit検証を実行します。

Xcode 26.3、Swift 6.2.4でアプリのコンパイル・リンクとテスト11件の成功を確認しています。Xcodeの選択状況は次のコマンドで確認できます。

```bash
xcode-select -p
xcodebuild -version
```

## アイコンを作り直す

アイコンは `Tools/generate_app_icon.swift` で描いた画像から作ります。デザインを変えたら、次のコマンドで `AppBundle/Resources/AppIcon.icns` を作り直し、アプリをビルドし直します。

```bash
./Scripts/make-icon.sh
./Scripts/build-app.sh
```

## リリースを作る

Apple Developer Programへの加入や署名証明書、Apple向けの認証情報は不要です。

バージョンの基準は `AppBundle/Info.plist` の `CFBundleShortVersionString`（現在は `0.1.0`）です。更新時はこの値と `CFBundleVersion` を更新し、対応する `releases/vX.Y.Z.md` に変更点と制限を書きます。タグは同じバージョンに `v` を付けます。

Apple SiliconのMacとXcode 26.3で、配布物をローカルに作れます。

```bash
./Scripts/test.sh
./Scripts/verify-pdfkit.sh
./Scripts/package-release.sh v0.1.0
```

`dist/v0.1.0/` に、Release構成でビルドしたアプリのZIPとSHA-256ファイルを出力します。ZIPを展開した状態で署名・バージョン・CPUアーキテクチャを検証します。開発用の `PaperPDFPrototype.app` は置き換えません。タグとアプリのバージョンが異なる場合や、リリースノートがない場合は停止します。

GitHubのリポジトリに接続してコードをpushした後、リリースするコミットにタグを付けて送ります。

```bash
git tag -a v0.1.0 -m "Paper PDF Prototype v0.1.0"
git push origin v0.1.0
```

`.github/workflows/release.yml` がmacOSのランナーとXcode 26.3でテスト、PDFKit検証、ZIP作成を行い、ZIP・SHA-256・リリースノート付きの **Draft Release** を作ります。GitHub標準の `GITHUB_TOKEN` を使用するので、個人アクセストークンの登録は不要です。失敗後の再実行では同じ下書きを更新し、公開済みのリリースは変更しません。

公開前には、下書きからダウンロードしたZIPで次を確認します。

- 初回の起動許可を経てPDFを開ける
- 線・付箋・ページメモを残して終了し、再起動すると復元される
- ページ位置が復元され、見開き・ズーム・取り消しを操作できる
- 可能なら別のMacでも起動できる。macOS 14での実機確認が未実施なら、その旨をリリースノートに追記する

確認後、GitHubのReleases画面で下書きを公開します。自動では公開しません。

標準のGitHub Actionsランナーは公開リポジトリでは無料です。非公開リポジトリでは無料枠と従量料金があるため、費用を避けたい場合はローカルで作ったZIPとSHA-256を手動でReleaseに添付できます。[GitHubのランナーと料金の説明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## 次の検証候補

- 翔泳社PDFを数冊使った表示・文字選択・権限の比較
- 選択文字のベースラインに吸着する「補助付き鉛筆線」
- 図やコードブロックへの矩形メモ
- ページ滞在時間を使った、読み飛ばしと読書の区別

## ライセンス

MIT License（[LICENSE](LICENSE)）。
