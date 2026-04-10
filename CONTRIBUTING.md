# Contributing to Nexus Network

このリポジトリは “動くPoC” を **外部コラボが安全に拡張できる実装基盤**へ進化させる段階にあります。  
`TECHNICAL_WHITEPAPER.md` を **最優先の設計図**として扱い、特に次の不変条件を守ってください。

- **Swarm（libp2p）をブロックしない**: 推論/重いI/Oは必ず `spawn_blocking` または専用ワーカーへ
- **ホットパスの不要な alloc/clone を避ける**
- **CI（fmt/clippy/test）を常にグリーンに保つ**

補助ドキュメント:

- **WHITE_PAPER.md** — 投資家・パートナー向けの全体像（実装の最終設計図は引き続き `TECHNICAL_WHITEPAPER.md`）
- **整合性（スラッシング）デモ** — `README.md` の「Test the Integrity」（`NEXUS_SIMULATE_FRAUD=1`）

---

## Quick Start（Issue #18: 品質検証デモ）

依存:
- `cargo`
- `curl`
- `jq`

実行（Seed→安定化→Client→REST→`verification_status=verified` を検証）:

```bash
./scripts/bootstrap.sh
```

互換（旧スクリプト名）:

```bash
./demo.sh
```

環境変数（必要に応じて上書き）:
- `NEXUS_GGUF_PATH`: GGUFモデルパス（推奨: `nexus-core/models/...`）
- `NEXUS_MODEL_ID`: モデルID（デモ既定: `nexus-infer-v1`）
- `NEXUS_REST_LISTEN`: REST bind（既定: `127.0.0.1:8080`）
- `NEXUS_API_KEY`: REST API key（既定: `steve-secret-key`）
- `NEXUS_VERIFICATION_RATE`: Double-check サンプリング率（既定: `1.0`）

---

## Code Map（どこに何があるか）

PoC は境界を分けてスケール可能にする方針です（`TECHNICAL_WHITEPAPER.md` 準拠）。

- **P2P / Swarm ループ**: `nexus-core/src/network.rs`
  - request/response（タスク提出/結果配送）
  - gossipsub（トピック購読/イベント処理）
  - slashing（ban + evidence永続化）周辺
- **推論ワーカー（llama.cpp）**: `nexus-core/src/inference_worker.rs`
  - **GGUFを1回ロードして context を再利用**
  - Swarm と推論の分離（`spawn_blocking`）
- **署名/検証（Ed25519）**: `nexus-core/src/signing.rs`
  - `InferenceResult` 署名付与と検証
- **Tiering/統計**: `nexus-core/src/tiering.rs`, `nexus-core/src/stats.rs`
  - ノード評価、スケジューリングの材料
- **REST API**: `nexus-core/src/rest.rs`
  - `POST /v1/chat/completions`
  - `metadata.verification_status` の付与（Optimistic Verification）

---

## Dev Workflow

ローカルで基本チェック:

```bash
cd nexus-core
cargo fmt
cargo clippy --all-targets --all-features -D warnings
cargo test
```

パフォーマンス/境界の注意:
- **Swarm の select loop** を重くしない（DBや推論は別スレッド/別ワーカー）
- 大量ログや巨大JSONの常時生成を避ける（必要な時だけ）
- bounded channel / 明示的な上限を維持する

