# AGENTS.md (Current Spec)

## リポジトリ
- Canonical: https://github.com/1amageek/swift-skeleton
- 本仕様の更新対象はこのリポジトリを正とする。

## Ignore / 生成物ポリシー
- 生成物・実行時ファイルはコミットしない。
- indexer/daemonの作業ディレクトリは原則 `.skeletonindex/` 配下に集約する。
- ソケット、PID、ログなどのランタイムファイルは常に一時物として扱う。
- 秘匿情報（`.env` など）は追跡対象にしない。

## 目的
- 「当たり付け最優先」で宣言スケルトンと位置情報を高速に返す。
- 組み込みパーサはASTから短い実装証拠を生成し、レビュー対象を`[impl:*]`で示す。
- 関数本文は保持しない。詳細はヒット後に原文へジャンプして確認する。
- パース不全でも停止しない。部分出力し、不確実性を明示する。

## スコープ
- 対象: Swift / Kotlin / TypeScript / Go / Zig / Rust / C++ / Python / Java
- 実装: Swift + SPM
- 形態:
  - Embedded: ライブラリ呼び出し
  - Sidecar: 常駐デーモン + JSON-RPC 2.0 (stdin/stdout)
- CLI: `skltn`
- パーサ: 各言語のTree-sitter grammar
- 対応OS: macOS優先

## 非スコープ
- 名前解決
- 型推論
- 関数本文の保持・出力
- call graph生成や意味的な呼び出し解決
- 実装アルゴリズムの正当性証明
- LSP統合
- コメント保持やコード整形

## 出力契約（必須）
- ブロック単位は `type` / `extension`。
- 並び順:
  - files: path 昇順
  - blocks: 出現順
  - props/methods: 出現順
- ヘッダ形式:
  - `class/struct/enum/protocol`: `<kw> <TypeName>: <Inheritance...> [<file>:<start>-<end>]`
  - `extension`: `extension <TypeName>: <Protocols...> [<file>:<start>-<end>]`
  - 継承・準拠が空なら `:` 以降は省略
- props:
  - `props: <name>:<TypeRef>, ...`
  - 型注釈なしは出力しない
- methods:
  - `<name>(<ParamTypeRef...>) -> <ReturnTypeRef> [<start>-<end>]`
  - `init(<ParamTypeRef...>) [<start>-<end>]`
  - 引数型不明は `?`、戻り型不明は `->` を省略
- エラー表示:
  - ファイル先頭に `# parse_error <filePath>`
  - ブロック内にERRORがあればヘッダ末尾に `(!)`
  - 不明は `?`（例: `[?-?]`, `start-?`）
- 実装シグナル:
  - ブロックヘッダ末尾: `[impl:<domains>]`
  - メソッド末尾: `[impl!:<reason>]` または `[impl?:<reason>]`
  - reasons: `trap` / `empty` / `const` / `noop` / `flow` / `error` / `wire` / `dead`
  - `--headers-only`はブロック単位の実装シグナルを保持する。

## アーキテクチャ境界
- `Core`
  - parse/build/update/queryの純機能
  - Skeletonテキスト、メタデータ、Implementation Fingerprintを生成
- `TreeSitterSupport`
  - Tree-sitterノードを本文非保持の実装証拠へ縮約
- Language Parsers
  - Tree-sitterノードから宣言、range、実装証拠を抽出
- `Client`
  - `SkeletonIndexService` プロトコルを公開
  - `EmbeddedService` と `SidecarService` を透過化
- `Daemon`
  - project open/close
  - status/diagnostics/update/query応答
  - watchは任意（未実装でもv1可）
- `CLI`
  - one-shot用途（`get` / `query` / `status` / `diagnostics` / `files` / `languages`）
  - `get`が正式な取得コマンド。`skeleton` / `get_skeleton` / `build`は互換alias。

## SPM構成
- Products:
  - `SkeletonIndexCore` (library)
  - `SkeletonSwiftParser`ほか言語別parser libraries
  - `SkeletonIndexClient` (library)
  - `skltn` (executable)
- Targets:
  - Core / TreeSitterSupport / Language Parsers / Client / CLI / Tests

## ディレクトリ規約
- `/Users/1amageek/Desktop/swift-skeleton/Sources/SkeletonIndexCore`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/SkeletonTreeSitterSupport`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/SkeletonIndexClient`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/Skeleton<Language>Parser`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/skltn`
- `/Users/1amageek/Desktop/swift-skeleton/Tests` はターゲット対応で分割する

## IPC契約
- JSON-RPC 2.0
- methods:
  - `index.open`
  - `index.status`
  - `index.get_skeleton`
  - `index.update`
  - `index.query`
  - `index.diagnostics`
- `index.query` は skeleton text 検索。ランキングは簡易実装で可。

## Implementation Fingerprint契約
- 組み込みパーサはTree-sitter ASTが生存している間にcall / return / write / branch / catch / trapを証拠へ縮約する。
- Coreへ関数本文テキストを渡して保持しない。
- AST証拠を提供しない互換パーサにはrange-based fallback解析を適用する。
- `wire`はfake-like型がproduction sourceでcallまたはconstruction targetになった場合のheuristicとする。
- `dead`はprivateメソッドにproduction code上の参照がない場合のheuristicとし、コメントと文字列は参照に数えない。
- シグナルは意味的正当性の証明ではない。原文確認を必須とする。

## テスト方針
- テストは小さく分割して実行する。
- 各テスト実行はタイムアウト付きにする（推奨30秒）。
- 少なくとも以下を自動検証する:
  - 並び順の安定性
  - 型注釈なしpropsの省略
  - 引数型不明 `?`
  - `parse_error` と `(!)` の表示
  - file/range の正しさ
  - 9言語のAST実装証拠
  - `trap` / `empty` / `const` / `noop` / `flow` / `error`の検出と誤検知回帰
  - `wire` / `dead`のproduction context判定
  - `skltn get`、省略形、互換alias
- `SKLTN_E2E_EXECUTABLE`でrelease版またはインストール済みCLIをE2E対象に指定できること。

## 実装ルール
- 関数本文テキストを保存しない。
- `try?` を使わない。`throws` または `do-catch` で扱う。
- 1ファイル1主要型を基本にする。
- 共有状態はSwift Concurrencyで安全に扱う（I/Oや順序保証が必要ならactor）。
- Sidecar IPCエラーはJSON-RPCエラーとして返し、黙殺しない。

## 受け入れ条件（DoD）
- Embedded/Sidecarで同一の問い合わせ機能が使える。
- 仕様の出力契約に一致するスケルトンを生成できる。
- パース失敗を含むプロジェクトで処理継続できる。
- `index.query` が file+range を返し、原文ジャンプに必要な情報を満たす。
- 組み込み9言語がAST証拠を生成し、本文を保持せずImplementation Fingerprintを出力できる。
- README、SKILL、埋め込みSKILL、インストール済みSKILL、CLI helpのコマンド契約が一致する。
