# AGENTS.md (Spec v1.1)

## リポジトリ
- Canonical: https://github.com/1amageek/swift-skeleton
- 本仕様の更新対象はこのリポジトリを正とする。

## Ignore / 生成物ポリシー
- 生成物・実行時ファイルはコミットしない。
- indexer/daemonの作業ディレクトリは原則 `.skeletonindex/` 配下に集約する。
- ソケット、PID、ログなどのランタイムファイルは常に一時物として扱う。
- 秘匿情報（`.env` など）は追跡対象にしない。

## 目的
- v1は「当たり付け最優先」。宣言スケルトンと位置情報だけを高速に返す。
- 関数本文は保持しない。詳細はヒット後に原文へジャンプして確認する。
- パース不全でも停止しない。部分出力し、不確実性を明示する。

## スコープ（v1）
- 対象: Swift
- 実装: Swift + SPM
- 形態:
  - Embedded: ライブラリ呼び出し
  - Sidecar: 常駐デーモン + JSON-RPC 2.0 (stdin/stdout)
- パーサ: Tree-sitter Swift grammar
- 対応OS: まずは macOS 優先（watchはv1任意）

## 非スコープ（v1）
- 名前解決
- 型推論
- 関数本文抽出、呼び出し抽出
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

## アーキテクチャ境界
- `Core`
  - parse/build/update/queryの純機能
  - Tree-sitterノードから宣言とrangeを抽出
  - Skeletonテキストとメタデータを生成
- `Client`
  - `SkeletonIndexService` プロトコルを公開
  - `EmbeddedService` と `SidecarService` を透過化
- `Daemon`
  - project open/close
  - status/diagnostics/update/query応答
  - watchは任意（未実装でもv1可）
- `CLI`
  - one-shot用途（build/get_skeleton/query）

## SPM構成目標
- Products:
  - `SkeletonIndexCore` (library)
  - `SkeletonIndexClient` (library)
  - `skeletonindexd` (executable)
  - `skeletonindex` (executable)
- Targets:
  - Core / Client / Daemon / CLI / Tests

## ディレクトリ規約（実装時）
- `/Users/1amageek/Desktop/swift-skeleton/Sources/SkeletonIndexCore`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/SkeletonIndexClient`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/skeletonindexd`
- `/Users/1amageek/Desktop/swift-skeleton/Sources/skeletonindex`
- `/Users/1amageek/Desktop/swift-skeleton/Tests` はターゲット対応で分割する

## IPC契約（v1最小）
- JSON-RPC 2.0
- methods:
  - `index.open`
  - `index.status`
  - `index.get_skeleton`
  - `index.update`
  - `index.query`
  - `index.diagnostics`
- `index.query` は skeleton text 検索。ランキングは簡易実装で可。

## 実装優先順位
1. Package再編（products/targetsを仕様名に合わせる）
2. CoreのAST抽出モデル（type/extension/props/methods/range）
3. Formatter（出力契約を満たすテキスト生成）
4. プロジェクト単位indexと差分update
5. Embedded Client
6. Sidecar Daemon（JSON-RPC loop）
7. Sidecar Client
8. CLI
9. テスト整備（順序安定性、parse_error、不完全ブロック、query）

## テスト方針
- テストは小さく分割して実行する。
- 各テスト実行はタイムアウト付きにする（推奨30秒）。
- 少なくとも以下を自動検証する:
  - 並び順の安定性
  - 型注釈なしpropsの省略
  - 引数型不明 `?`
  - `parse_error` と `(!)` の表示
  - file/range の正しさ

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
