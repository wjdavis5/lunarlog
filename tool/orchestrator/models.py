"""OpenCode model roster and role mapping.

The roster is discovered at runtime with `opencode models`; the role defaults
below are the fallback and the starting point for a per-dispatch override.
"""

from __future__ import annotations

import subprocess

DEFAULT_ROLE_MODELS = {
    "planner": "deepseek/deepseek-v4-flash",
    "reviewer": "deepseek/deepseek-v4-flash",
    "coder": "opencode/muse-spark-1.3-contributor-free",
}

TIMEOUT_SECONDS = 60


class ModelError(RuntimeError):
    """A model id was unknown or the roster could not be read."""


def _runner(cmd):
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=TIMEOUT_SECONDS,
    )


def available_models(runner=_runner) -> list[str]:
    """Every model id `opencode models` reports, one per line."""
    proc = runner(["opencode", "models"])
    if proc.returncode != 0:
        raise ModelError(f"opencode models failed: {(proc.stderr or '').strip()}")
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def resolve_model(role: str, override: str | None = None, available: list[str] | None = None) -> str:
    """Resolve a role to a validated model id. Override wins over the default.

    `available` is optional so callers that already hold the roster avoid a
    second `opencode models` call; when omitted it is fetched."""
    model = override or DEFAULT_ROLE_MODELS.get(role)
    if not model:
        raise ModelError(f"no model mapped for role {role!r}")
    if available is None:
        available = available_models()
    if model not in available:
        raise ModelError(f"model {model!r} for role {role!r} is not in the roster")
    return model


def _main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--role", required=True)
    ap.add_argument("--override", default=None)
    ap.add_argument("--available", action="store_true", help="print the whole roster and exit")
    args = ap.parse_args()
    try:
        if args.available:
            print("\n".join(available_models()))
            return 0
        print(resolve_model(args.role, override=args.override))
    except ModelError as e:
        print(f"error: {e}", file=__import__("sys").stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
