## Nexus REST API (PoC)

Client ノードは OpenAI 風の REST API を提供します。内部的には Nexus Network に `InferenceTask` を投入し、**署名検証済みの結果**だけを返します。

### 有効化

- **Client ノード**で REST を起動します（Seed では起動しません）
- 外部公開する場合は `NEXUS_REST_LISTEN=0.0.0.0:8080` のように設定します

必要な環境変数:
- **`NEXUS_API_KEY`**: APIキー（未設定だと 401 で fail-closed）
- **`NEXUS_REST_LISTEN`**: listen addr（例 `0.0.0.0:8080`）
- **`NEXUS_ALLOWED_ORIGINS`**: CORS許可 origin（CSV）。未設定なら全許可（PoC）。

### エンドポイント

#### `POST /v1/chat/completions`

```bash
curl -s "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: ${NEXUS_API_KEY}" \
  -d '{
    "model": "nexus-infer-v1",
    "messages": [{"role":"user","content":"Hello"}],
    "high_priority": true,
    "max_tokens": 128
  }' | jq .
```

レスポンスは `metadata` に `node_tier` と `virtual_balance` を含みます。

