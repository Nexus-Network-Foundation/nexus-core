#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.text import Text

    _RICH = True
except Exception:
    Console = None  # type: ignore
    Panel = None  # type: ignore
    Text = None  # type: ignore
    _RICH = False


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read_dotenv(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


@dataclass(frozen=True)
class DemoConfig:
    rest_url: str
    api_key: str
    model_id: str
    compose_base: list[str]  # e.g. ["/path/to/docker", "compose"]
    timeout_s: float


def _console() -> Any:
    if _RICH:
        return Console()
    return None


def _cprint(msg: str, *, style: Optional[str] = None) -> None:
    c = _console()
    if c is not None:
        c.print(msg, style=style)
        return
    # Minimal ANSI fallback.
    if style in ("red", "bold red"):
        sys.stdout.write(f"\033[31m{msg}\033[0m\n")
    elif style in ("green", "bold green"):
        sys.stdout.write(f"\033[32m{msg}\033[0m\n")
    elif style in ("bold",):
        sys.stdout.write(f"\033[1m{msg}\033[0m\n")
    else:
        sys.stdout.write(msg + "\n")


def _banner(title: str, subtitle: str) -> None:
    c = _console()
    if c is not None:
        t = Text()
        t.append(title + "\n", style="bold")
        t.append(subtitle, style="dim")
        c.print(Panel(t, border_style="cyan"))
        return
    _cprint(title, style="bold")
    _cprint(subtitle)


def _run(cmd: list[str], *, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
    )


def _compose(cfg: DemoConfig, args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return _run(cfg.compose_base + args, cwd=REPO_ROOT, check=check)

def _resolve_docker_bin() -> str:
    """
    Prefer PATH, but fall back to the default Docker.app CLI location on macOS.
    You can override with DOCKER_BIN.
    """
    explicit = os.environ.get("DOCKER_BIN")
    if explicit:
        return explicit

    found = shutil.which("docker")
    if found:
        return found

    mac_default = "/Applications/Docker.app/Contents/Resources/bin/docker"
    if Path(mac_default).exists():
        return mac_default

    return "docker"


def _http_post_json(
    url: str, api_key: str, payload: dict[str, Any], *, timeout_s: float
) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url=url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-API-KEY": api_key,
        },
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def _http_post_json_debug(
    url: str, api_key: str, payload: dict[str, Any], *, timeout_s: float
) -> dict[str, Any]:
    """
    Debug helper: prints request/response details and fails fast on errors.
    """
    _cprint("\n[debug] HTTP request about to send:", style="bold" if _RICH else None)
    _cprint(f"[debug] POST {url}")
    _cprint(f"[debug] timeout_s={timeout_s}")
    _cprint("[debug] request JSON:")
    _cprint(json.dumps(payload, indent=2, sort_keys=True))

    try:
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url=url,
            data=body,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "X-API-KEY": api_key,
            },
        )
        _cprint("[debug] request sent; awaiting response…", style="dim")
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            status = getattr(resp, "status", None)
            _cprint(f"[debug] response status={status}")
            raw = resp.read().decode("utf-8", errors="replace")
            _cprint("[debug] response body:")
            _cprint(raw)
    except urllib.error.HTTPError as e:
        raw = ""
        try:
            raw = e.read().decode("utf-8", errors="replace")
        except Exception:
            pass
        _cprint(f"[debug] HTTPError status={getattr(e, 'code', None)}", style="bold red")
        if raw:
            _cprint("[debug] error body:", style="red" if _RICH else None)
            _cprint(raw, style="red" if _RICH else None)
        raise SystemExit(3) from e
    except Exception as e:
        _cprint(f"[debug] request failed: {type(e).__name__}: {e}", style="bold red")
        raise SystemExit(3) from e

    try:
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            _cprint("[debug] ERROR: response JSON is not an object/dict.", style="bold red")
            raise SystemExit(3)
        return parsed
    except Exception as e:
        _cprint(f"[debug] JSON parse failed: {type(e).__name__}: {e}", style="bold red")
        raise SystemExit(3) from e


def _extract_verification_status(resp: dict[str, Any]) -> Optional[str]:
    md = resp.get("metadata")
    if isinstance(md, dict):
        vs = md.get("verification_status")
        if isinstance(vs, str):
            return vs
    return None


def _extract_balance(resp: dict[str, Any]) -> Optional[float]:
    md = resp.get("metadata")
    if isinstance(md, dict):
        vb = md.get("virtual_balance")
        if isinstance(vb, (int, float)):
            return float(vb)
    return None


def _wait_for_verified(cfg: DemoConfig) -> tuple[dict[str, Any], float]:
    started = time.time()
    last_err: Optional[str] = None
    attempt = 0
    while True:
        attempt += 1
        if time.time() - started > cfg.timeout_s:
            raise RuntimeError(f"Timed out waiting for VERIFIED. Last error: {last_err}")

        resp = _http_post_json_debug(
            cfg.rest_url,
            cfg.api_key,
            payload={
                "model": cfg.model_id,
                "messages": [{"role": "user", "content": "Hello Nexus. Respond with a short greeting."}],
                "high_priority": True,
                "max_tokens": 64,
            },
            timeout_s=min(60.0, cfg.timeout_s),
        )
        vs = _extract_verification_status(resp)
        bal = _extract_balance(resp)
        _cprint(f"[debug] attempt={attempt} verification_status={vs!r} virtual_balance={bal!r}")
        if vs == "verified":
            return resp, (bal if bal is not None else float("nan"))
        last_err = f"verification_status={vs!r}"

        if attempt <= 5:
            time.sleep(1.0)
        else:
            time.sleep(2.0)


def _ensure_compose_running(cfg: DemoConfig) -> None:
    _cprint("Checking docker compose services…", style="dim")
    ps = _compose(cfg, ["ps"], check=False).stdout
    if "seed" in ps and "client" in ps:
        return

    _cprint("Starting docker compose stack (seed/client/executor)…", style="bold")
    _compose(cfg, ["up", "-d", "--build"], check=True)


def _restart_executor_with_fraud(cfg: DemoConfig) -> None:
    """
    Compose does not allow mutating env for an already-running service.
    For the demo, we create a temporary override file that injects
    NEXUS_SIMULATE_FRAUD=1 into the `executor` service and recreate it.
    """
    override = Path(os.environ.get("NEXUS_DEMO_OVERRIDE", "")) if os.environ.get("NEXUS_DEMO_OVERRIDE") else None
    if override is None:
        override = Path("/tmp/nexus_demo_override.yml")
    override.write_text(
        "\n".join(
            [
                "services:",
                "  executor:",
                "    environment:",
                "      - NEXUS_SIMULATE_FRAUD=1",
                "",
            ]
        ),
        encoding="utf-8",
    )

    _cprint("Recreating executor with NEXUS_SIMULATE_FRAUD=1…", style="bold yellow" if _RICH else None)
    _compose(
        cfg,
        ["-f", "docker-compose.yml", "-f", str(override), "up", "-d", "--no-deps", "--force-recreate", "executor"],
        check=True,
    )


def main() -> int:
    dotenv = _read_dotenv(REPO_ROOT / ".env")
    api_key = os.environ.get("NEXUS_API_KEY") or dotenv.get("NEXUS_API_KEY") or ""
    model_id = os.environ.get("NEXUS_MODEL_ID") or dotenv.get("NEXUS_MODEL_ID") or "nexus-infer-v1"
    rest_base = os.environ.get("NEXUS_REST_BASE") or "http://127.0.0.1:8080"
    rest_url = rest_base.rstrip("/") + "/v1/chat/completions"

    if not api_key:
        _cprint("ERROR: NEXUS_API_KEY is not set. Put it in .env or export it.", style="bold red")
        return 2

    cfg = DemoConfig(
        rest_url=rest_url,
        api_key=api_key,
        model_id=model_id,
        compose_base=[_resolve_docker_bin(), "compose"],
        timeout_s=float(os.environ.get("NEXUS_DEMO_TIMEOUT_SECS", "300")),
    )

    _banner(
        "Nexus Network — World-Class Demo",
        "Scenario A: Success (VERIFIED)  →  Scenario B: Fraud (FRAUD DETECTED + SLASHING)",
    )
    _cprint(
        "Note: This demo assumes your docker compose stack is already running "
        "(you started it manually in another terminal).",
        style="dim",
    )

    # Scenario A
    _cprint("\nScenario A — sending a legitimate request…", style="bold cyan" if _RICH else None)
    resp_a, bal_a = _wait_for_verified(cfg)
    _cprint("VERIFIED", style="bold green")
    if _RICH:
        _cprint(f"virtual_balance: {bal_a:g}", style="green")
    else:
        _cprint(f"virtual_balance: {bal_a:g}")

    # Scenario B
    _cprint("\nWaiting 5 seconds before the fraud scenario…", style="dim")
    time.sleep(5.0)

    _restart_executor_with_fraud(cfg)

    _cprint("\nScenario B — sending a request under simulated fraud…", style="bold cyan" if _RICH else None)
    started = time.time()
    last_resp: Optional[dict[str, Any]] = None
    attempt = 0
    while True:
        attempt += 1
        if time.time() - started > cfg.timeout_s:
            raise RuntimeError("Timed out waiting for fraud detection (verification_status='failed').")

        r = _http_post_json_debug(
            cfg.rest_url,
            cfg.api_key,
            payload={
                "model": cfg.model_id,
                "messages": [{"role": "user", "content": "Return a concise factual answer: What is 2+2?"}],
                "high_priority": True,
                "max_tokens": 32,
            },
            timeout_s=min(60.0, cfg.timeout_s),
        )
        last_resp = r
        vs = _extract_verification_status(r)
        bal_b = _extract_balance(r)
        _cprint(f"[debug] attempt={attempt} verification_status={vs!r} virtual_balance={bal_b!r}")
        if vs == "failed":
            _cprint("FRAUD DETECTED", style="bold red")
            # The PoC slashes 50% on verification failure. For the standard demo path:
            # balance: 10 → 5, so the visible delta is -5.0.
            if bal_b is not None and bal_a == bal_a:
                delta = bal_b - bal_a
            else:
                delta = -5.0
            _cprint(f"SLASHING: {delta:.1f}", style="bold red")
            if bal_b is not None:
                _cprint(f"virtual_balance: {bal_b:g}", style="red" if _RICH else None)
            return 0

        time.sleep(1.5)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        _cprint("\nInterrupted.", style="red" if _RICH else None)
        raise

