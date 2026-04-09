# Nexus Network Technical Whitepaper — `nexus-core` Ultimate Blueprint

> Version: Draft (living document, 2026-04-09)  
> Scope: `nexus-core` (Rust 2024) — high-performance, scalable, edge-first inference network  
> Inference: `llama-cpp-2` (llama.cpp) with optional `metal` feature on Apple Silicon  
> Networking: `libp2p` (Gossipsub over TCP + Noise + Yamux)  
> Principle: **Performance is a feature. Automation is an invariant.**

---

## 1. Executive Summary

Nexus Network は、**中央集権的な AI 推論を解体し、エッジデバイスへ知能を取り戻す**ことを目標にした分散推論ネットワークである。  
本書は `nexus-core` を “動くデモ” で終わらせず、**高性能**と**スケーラビリティ**を両立するための最終設計図として、以下を定義する。

- **性能目標（SLO）**: 低レイテンシ、安定スループット、予測可能なメモリ使用量
- **スケール戦略**: ノード数増加・トピック増加・モデル多様化に耐えるネットワーク/実行基盤
- **実装規律**: ボトルネックの分離（Swarm と推論の分離）、ブロッキングの排除、計測可能性
- **運用自動化**: “手動はバグ” として扱い、CI/自動修正/キャッシュ/依存更新を不変条件にする

---

## 2. Design Goals

### 2.0 Non-Negotiables（絶対に破ってはいけない不変条件）

- **Swarm は止めない**: 推論・I/O・重い処理で `libp2p` のポーリングをブロックしない
- **ホットパスは割り当てを減らす**: クリティカル経路で不要な `String` / `Vec` / clone を増やさない
- **計測できないものは最適化できない**: 重要なレイテンシ/メモリ/スループットは計測点を必ず持つ
- **自動化に逆らわない**: fmt/clippy/CI を前提に設計し、手動チェックに依存しない

### 2.1 開発効率（Developer Velocity）

- **手動作業の排除**: フォーマット・軽微な自動修正・依存更新・CI の実行をすべて自動化
- **高速フィードバック**: CI の待ち時間を最短化し、変更の安全性を “常時可視化”
- **再現性**: ローカルと CI の挙動差を極小にし、環境要因で壊れない開発体験を維持

### 2.2 拡張性（Extensibility）

- **境界（Boundaries）を壊さない**: “ドメイン/アプリ/インフラ” の関心を分離し、置換可能に保つ
- **推論基盤の差し替え**: `llama-cpp-2` を入口にしつつ、将来の別 backend（CUDA / Vulkan / remote providers）へ拡張可能
- **ネットワーク拡張**: gossip から request/response、ルーティング、スケジューリング、検証（ZK/サンプリング）へ段階的に移行可能

---

## 3. System Overview (Current PoC)

### 3.1 コンポーネント

- **Client Node**
  - REPL（`nexus> `）でユーザーの入力を受け、`InferenceTask` を生成して P2P に publish
  - 直送（request/response）で `InferenceResult` を受け取り、整形表示

- **Seed Node (`--server`)**
  - 固定ポートで待ち受け、P2P mesh のブートストラップ点になる
  - `InferenceTask` を受け取り、ヘルス（Ping/Pong）と DB 統計を使って executor を選択
  - 結果はブロードキャストせず、`origin_peer_id` へ直送

- **Inference Engine**
  - 起動時に **GGUF を 1 回だけロード**し、各タスクは `spawn_blocking` 上で推論
  - Apple Silicon の場合 `--features metal` により llama.cpp の Metal backend を活用

### 3.2 データモデル（Wire Format）

- `InferenceTask`（JSON）
  - `id`, `request_id`, `origin_peer_id`, `model`, `prompt`, `max_tokens`, `requester_node_id_hash`, `created_at_unix_ms`
- `InferenceResult`（JSON）
  - `task_id`, `request_id`, `origin_peer_id`, `executor_peer_id`, `executor_signature`, `model`, `output`, `ok`, `finished_at_unix_ms`
  - `inference_started_at_unix_ms`, `inference_finished_at_unix_ms`

これらは PoC 段階の “最小契約” として定義し、将来的な署名・バージョニング・互換性戦略の追加を想定する。

---

## 4. Performance Architecture: Network ↔ Inference

### 4.1 libp2p (Gossipsub) の役割

PoC の要点は「推論は重い。Swarm のポーリングは軽い」を守ることである。

- Swarm は **メッセージ取り回し**に専念
- 推論は **tokio mpsc** でワーカーへオフロード
- 推論結果は **別チャネル**で swarm ループへ戻し、`nexus-results` に publish

この設計により、推論が遅延しても P2P の健全性（ハンドシェイク・メッシュ維持・購読）は崩れにくい。

#### 4.1.1 スケールの論点（Gossipsub の限界を理解して使う）

Gossipsub は PoC の “最小の全体通信” として強力だが、ノード数増加に伴い以下がボトルネックになり得る。

- **結果のブロードキャストの過剰**: `InferenceResult` を全ノードへ撒く設計は帯域を浪費する  
  → 将来は request/response（宛先制御）や、結果のルーティング/サブスク分割が必要
- **メッシュ形成と `InsufficientPeers`**: publish 直後は購読伝播が間に合わない  
  → 現行は mesh retry で吸収（将来は接続管理/プロトコルで根治）
- **スパム/DoS**: Permissive validation は実運用では危険  
  → レート制限、署名、メッセージサイズ上限、ピアスコアリングが必須

### 4.2 llama.cpp (llama-cpp-2) の役割

`llama-cpp-2` は llama.cpp の高速な C++ 実装を Rust から利用するための実運用向けバインディングである。

- **GGUF のローカルロード**（`NEXUS_GGUF_PATH` でモデルパス指定）
- **コンテキスト生成**と **トークン生成ループ**
- Apple Silicon では `metal` feature で GPU オフロードを利用可能

PoC では “まず動く” を優先しつつ、推論の境界を `LlamaEngine` に閉じ、将来の engine 差し替え（別モデル/別 runtime/remote）に備える。

#### 4.2.1 性能の論点（推論ホットパス）

高性能化の優先順位は次の通り。

- **(A) 1回ロード**: GGUF のロードは起動時に 1 回だけ（既に達成）
- **(B) Context 再利用**: タスクごとに context を作るのは安全だがコストが大きい  
  → 将来は “worker-local context pool” を導入し、同一スレッド上で再利用する
- **(C) トークナイズ/デトークナイズ**: `token_to_piece` は地味に重い  
  → 可能なら出力を token ベースでバッファし、まとめてデコード/もしくは streaming へ
- **(D) KV/CTX サイズ管理**: `n_ctx` と `n_batch` の過剰設定はメモリを爆発させる  
  → `max_tokens` と prompt 長から “必要最小” を計算し、上限を明確にする

---

## 5. Development Productivity: Automation as a First-Class Feature

Nexus Network は「自動化」を補助輪ではなく、**設計要件**として扱う。理由は単純で、分散システム + 推論基盤は複雑であり、手動運用は必ず破綻するためである。

### 5.1 CI Gateway（壊れたコードの流入を防ぐ）

GitHub Actions で以下を自動化している（`/.github/workflows/ci.yml`）。

- **PR / main push**
  - Linux: `cargo build` / `cargo test` / `cargo clippy -D warnings`
  - macOS: `cargo check --features metal`

これにより “動かない PR” を構造的に混入させない。

### 5.2 Auto-fix & Commit（清潔なリポジトリを維持）

push 時に `cargo fmt` を実行し、差分があれば Actions が自動コミットする。  
さらに（オプションとして）`cargo clippy --fix` を non-blocking で試行し、機械的に直せる範囲は自動で解消する。

### 5.3 sccache（最優先：CI 待ち時間の削減）

Rust のビルドは重い。CI の待ち時間は開発者の集中力を削る。  
そこで CI に **sccache（GHA バックエンド）**を導入し、コンパイル成果物をキャッシュする。

- `RUSTC_WRAPPER=sccache`
- `SCCACHE_GHA_ENABLED=true`
- `mozilla-actions/sccache-action` + `Swatinem/rust-cache`

この組み合わせで “初回は重いが、以後は最短” を狙う。

#### 5.3.1 キャッシュ戦略（最短 CI を維持するための原則）

- `Cargo.lock` が更新されない限り、依存ビルドは再利用されるべき
- sccache は “コンパイル結果” を保持し、`rust-cache` は “レジストリ/target” を補助する
- 目標は「PR の 2 回目以降は *ほぼリンクだけ*」の状態に近づけること

### 5.4 Dependabot（依存更新の無人化）

`/.github/dependabot.yml` により Cargo 依存の更新 PR を自動で生成する。  
CI と組み合わせることで “更新 PR が勝手に来て、勝手に壊れて、勝手に検出される” 状態を作り、依存老朽化の負債を最小化する。

---

## 6. Scalability Blueprint（スケールするための設計図）

PoC を “作り捨て” にしないための拡張設計を、最初から想定する。

### 6.1 推論エンジンの差し替え

`LlamaEngine` を `InferenceEngine` 的インターフェースへ抽象化し、次の拡張を可能にする:

- backend 多様化: `metal` / `cuda` / `vulkan` / `cpu`
- 実行モード: バッチ推論 / ストリーミング（token-by-token）/ embeddings
- ルールベース出力: grammar / JSON schema 生成（llama.cpp 機能の活用）
- リモート推論: gRPC/HTTP で外部推論ノードへ委譲

#### 6.1.1 推論ワーカー設計（スループット最適化）

将来の `nexus-core` は以下の worker モデルを目標にする。

- **固定数ワーカー + キュー**: ノード CPU/GPU に合わせた並列度（過剰 spawn を避ける）
- **優先度付きキュー**: 対話（低遅延）とバッチ（高スループット）を分離
- **キャンセル**: “もう要らない推論” を止める（クライアント disconnect 等）
- **streaming**: token streaming で体感レイテンシを改善し、途中での停止も可能にする

### 6.2 ネットワーク層の進化

Gossipsub は PoC の “最小の全体通信” として非常に有効だが、実運用のためには次を段階的に導入する:

- request/response（結果の宛先制御、帯域効率）
- ルーティング・スケジューリング（性能・信頼性・コスト）
- 実行証跡・検証（サンプリング、将来的な ZK/証明）
- レート制限・スパム対策（DoS・メッシュ汚染）

#### 6.2.1 結果の宛先制御（必須のスケール要件）

スケール時の最重要課題は “結果の撒きすぎ” である。

- 現行: `InferenceResult` を `nexus-results` でブロードキャスト
- 目標: “タスク送信者にだけ返す” を基本にし、必要に応じて集計/キャッシュ/再配布を行う

設計案:

- (1) `task_id` → `requester_peer` の対応表を持ち、request/response で返す
- (2) `nexus-results/<peer>` のようなトピック分割（購読を最小化）
- (3) 集計ノード（indexer）を追加し、結果を保存/検索可能にする

### 6.3 プロトコル互換性

JSON は PoC に最適だが、将来は versioned schema と互換性戦略が必要になる:

- `protocol_version` フィールドの追加
- 後方互換・前方互換のルール
- CBOR/MessagePack 等のバイナリフォーマットへの移行余地

---

## 7. Thermodynamic Slashing (Research Primitive)

Nexus は “効率” をネットワークの経済原理へ接続する。直観は次の通り:

\[
S = n \cdot R
\]

- \(n\): レイテンシ（遅延）
- \(R\): エネルギー（計算コスト）
- \(S\): ペナルティ（スラッシング/評価指標）

この指標は、単なるランキングではなく、将来的に:

- ルーティング選好（低 \(S\) のノードへ仕事を寄せる）
- 報酬配分（効率的なノードに報酬、非効率に罰則）
- Sybil 抵抗の一部（“物理” への接続による制約）

へ拡張されうる。

### 7.1 実測に基づく \(n, R\) 推定

“評価” を成立させるためには、推定を曖昧にしない。

- \(n\): ネットワーク往復 + 推論時間の内訳（キュー待ち、decode time 等）を分解して計測
- \(R\): エネルギーそのものは取得困難なため、当面は代理指標（GPU/CPU 使用率・消費電力 API など）を用い、後に精度を上げる

---

## 8. Operational Concerns (What We Intentionally Defer)

PoC の段階では以下を “あえて後回し” にしている（拡張は設計済みの前提）。

- 認証・署名（task/result の真正性）
- モデル配布（モデルの取得・検証・ライセンス管理）
- サンドボックス（安全な推論実行環境）
- 観測性（メトリクス/トレース/ログ集約）
- ストリーミング出力（token streaming）

---

## 9. Roadmap (Draft)

- **Phase 0 (Now)**: Rust + libp2p + llama.cpp で動く PoC、REPL、CI 自動化、キャッシュ最適化
- **Phase 1**: request/response で結果の宛先最適化、負荷制御、実行計測
- **Phase 2**: スケジューリングと “Thermodynamic Slashing” の統合（実測値から \(n, R\) を推定）
- **Phase 3**: 検証（サンプリング/証跡/将来的な ZK）と、モデル/ノードのガバナンス

---

## 10. Appendix: Build & Run Notes

- モデル指定: `NEXUS_GGUF_PATH=./models/llama-3-8b.gguf`
- macOS Metal: `cargo run --release --features metal`
- llama.cpp ビルド依存: CMake + C++ toolchain（例: macOS `brew install cmake`）

---

## 11. “Strict Adherence” Checklist (for future contributions)

このセクションは、将来の変更が “最終設計図” に沿っているかを判定するためのチェックリストである。

- **(perf) Swarm はブロックしていないか？**
- **(perf) 推論は必ず `spawn_blocking` / 専用ワーカーで実行されているか？**
- **(perf) クリティカルパスで不要な clone/alloc を増やしていないか？**
- **(scale) 結果の配布は宛先制御（または将来の移行余地）を考慮しているか？**
- **(ops) CI（fmt/clippy/test）と自動化に矛盾しないか？**
- **(ops) sccache キャッシュが効く変更になっているか？（無駄な再ビルドを誘発していないか）**

