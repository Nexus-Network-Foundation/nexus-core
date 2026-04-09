# Nexus Network

**中央集権的なAIを解体し、エッジデバイスに知能を取り戻す。**

クラウドの“囲い込み”ではなく、P2P と物理（レイテンシ・エネルギー）を前提にした分散推論の実行基盤を作ります。  
Nexus は **`libp2p (Gossipsub)`** で推論タスクをブロードキャストし、各ノードが **`llama.cpp (llama-cpp-2)`** で **GGUF** をローカル推論。Apple Silicon では **Metal** で GPU オフロードします。

---

## Interactive Demo

クライアントを起動すると `nexus> ` の REPL が立ち上がり、任意のプロンプトを入力できます。推論結果は P2P 経由で `nexus-results` として返り、ターミナルに整形表示されます。

```text
REPL: type a prompt and press Enter. 'exit' or 'quit' to stop.

nexus> Explain the future of decentralized AI in 3 points.
nexus> Waiting for mesh formation... (retry 1/10)
[p2p] published task to topic "nexus-tasks"

┌── Inference result (task_id=task-1) ──
│ ok: true
│ model: nexus-infer-mock-v1
│ finished_at_unix_ms: 1775715320451
├────────────────────────────────────────
│  What are the potential benefits and challenges of decentralized AI?
│ The future of decentralized AI is expected to be shaped by several factors...
│ 
│ 1. Increased Transparency and Security ...
│ 2. Improved Collaboration and Interoperability ...
│ 3. Enhanced Autonomy and Adaptability ...
└────────────────────────────────────────
```

### 実行方法（ローカル2ノード）

- **Seed（サーバー）**: 固定ポートで待ち受け続けます

```bash
cd nexus-core
NEXUS_GGUF_PATH=./models/llama-3-8b.gguf cargo run --release --features metal -- --server
```

- **Client（REPL）**: 自動で seed にダイアルし、REPL で入力したプロンプトを publish します

```bash
cd nexus-core
NEXUS_GGUF_PATH=./models/llama-3-8b.gguf cargo run --release --features metal
```

> 補足: `llama-cpp-2` は `llama.cpp` をソースからビルドするため **CMake が必要**です（macOS: `brew install cmake`）。

---

## REST API（PoC / 外部統合）

Client ノードは `axum` で簡易 REST API を提供します。ブラウザ/モバイルから使うために **CORS** と **API Key**（`X-API-KEY`）による最低限の防御を入れています。

- **API ドキュメント**: `DOCS/API.md`

---

## Architecture Visualized

```mermaid
flowchart LR
  subgraph Client["Client Node (REPL)"]
    REPL["tokio::io::stdin() REPL\nnexus> prompt"]
    CNET["libp2p Swarm\nGossipsub: nexus-tasks / nexus-results"]
    REPL -->|"InferenceTask(JSON)"| CNET
  end

  subgraph Seed["Seed Node (--server)"]
    SNET["libp2p Swarm\nGossipsub subscribe/publish"]
    DISPATCH["task_dispatch_tx\n(tokio mpsc)"]
    WORKER["inference_worker_loop\n(load GGUF once)"]
    LLAMA["llama-cpp-2\nllama.cpp backend"]
    METAL["Metal (Apple Silicon)\nGPU offload"]
    SNET -->|"nexus-tasks"| DISPATCH --> WORKER --> LLAMA --> METAL
    WORKER -->|"InferenceResult(JSON)"| SNET
  end

  CNET <--> |"P2P (TCP + Noise + Yamux)\nGossipsub mesh"| SNET
  SNET -->|"nexus-results"| CNET
```

要点:
- **タスク配布**: `InferenceTask` を JSON で `nexus-tasks` に publish
- **実推論**: seed/各ノードが GGUF をローカルロードし推論（Apple Silicon は Metal で高速化）
- **結果回収**: `InferenceResult` を JSON で `nexus-results` に publish → クライアントで表示

---

## Thermodynamic Slashing

Nexus はノード評価を「ステーク」だけに寄せず、**計算の物理コスト**を経済に直結させます。

- **狙い**: “速く・省エネで・再現性のある推論” を行うノードを正当に評価し、非効率なノードを自然に淘汰する
- **直観**: 遅延 \(n\) とエネルギー \(R\) の積をペナルティとして扱う

\[
S = n \cdot R
\]

この指標をネットワーク層のルーティング・スケジューリング・将来的なスラッシング（罰則）へ接続し、**“効率が正義”**の推論経済を構築します。

