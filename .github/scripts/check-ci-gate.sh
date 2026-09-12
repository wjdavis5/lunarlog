#!/usr/bin/env bash
# .github/scripts/check-ci-gate.sh
#
# Shared by ios-release.yml and play-store-release.yml (Issue #498).
#
# Gates release workflows on the successful completion of required CI check runs
# (Database tests (pgTAP), Edge Functions (deno test), and Analyze, test, build web).
# Fails closed unless all required checks on the target commit have completed
# with a 'success' conclusion.
#
# Inputs (env):
#   COMMIT_SHA             Commit SHA to verify. Defaults to git rev-parse HEAD.
#   GITHUB_REPOSITORY      GitHub repository (owner/repo). Defaults to 'wjdavis5/lunarlog'.
#   GH_TOKEN               GitHub API token (used by `gh api` or curl).
#   REQUIRED_CHECKS        Comma-separated list of required check run names.
#                          Defaults to:
#                            "Database tests (pgTAP),Edge Functions (deno test),Analyze, test, build web"
#   MAX_WAIT_SECONDS       Maximum seconds to wait for in-progress checks. Default: 1800 (30m).
#   POLL_INTERVAL_SECONDS  Seconds between polling iterations. Default: 15.
#   CHECK_RUNS_JSON_FILE   Optional path to a JSON file containing the check-runs API payload.
#                          When provided, skips network calls and reads check runs directly.
#                          Supports comma-separated file paths to simulate state progression across polls.
#
# Exit codes:
#   0: All required checks completed with 'success'.
#   1: One or more checks failed, cancelled, timed out, or not found after MAX_WAIT_SECONDS.
set -euo pipefail

COMMIT_SHA="${COMMIT_SHA:-}"
if [ -z "$COMMIT_SHA" ]; then
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    COMMIT_SHA="$(git rev-parse HEAD)"
  fi
fi

if [ -z "$COMMIT_SHA" ]; then
  echo "::error::COMMIT_SHA is not set and could not be determined from git."
  exit 1
fi

REPO="${GITHUB_REPOSITORY:-wjdavis5/lunarlog}"
# Delimited by '|' to safely support check names containing commas (such as "Analyze, test, build web")
REQUIRED_CHECKS="${REQUIRED_CHECKS:-Database tests (pgTAP)|Edge Functions (deno test)|Analyze, test, build web}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-1800}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

echo "Evaluating CI check runs for commit $COMMIT_SHA on $REPO..."
echo "Required checks: $REQUIRED_CHECKS"

fetch_check_runs() {
  local repo="$1" sha="$2"
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${repo}/commits/${sha}/check-runs?per_page=100"
  else
    local auth_header=()
    if [ -n "${GH_TOKEN:-}" ]; then
      auth_header=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi
    curl -sSL --fail ${auth_header[@]+"${auth_header[@]}"} \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repo}/commits/${sha}/check-runs?per_page=100"
  fi
}

start_time=$(date +%s)
iter=0

sim_files=()
num_sim_files=0
if [ -n "${CHECK_RUNS_JSON_FILE:-}" ]; then
  IFS=',' read -r -a sim_files <<< "$CHECK_RUNS_JSON_FILE"
  num_sim_files=${#sim_files[@]}
fi

while true; do
  now=$(date +%s)
  elapsed=$((now - start_time))

  if [ "$num_sim_files" -gt 0 ]; then
    idx=$iter
    if [ "$idx" -ge "$num_sim_files" ]; then
      idx=$((num_sim_files - 1))
    fi
    json_source="${sim_files[$idx]}"
    is_temp_file=0
  else
    tmp_json="$(mktemp)"
    is_temp_file=1
    if ! fetch_check_runs "$REPO" "$COMMIT_SHA" > "$tmp_json" 2>&1; then
      err_msg="$(cat "$tmp_json")"
      rm -f "$tmp_json"
      echo "::warning::Failed to fetch check runs: $err_msg"
      if [ "$elapsed" -ge "$MAX_WAIT_SECONDS" ]; then
        echo "::error::Timed out after ${MAX_WAIT_SECONDS}s unable to fetch check runs."
        exit 1
      fi
      sleep "$POLL_INTERVAL_SECONDS"
      iter=$((iter + 1))
      continue
    fi
    json_source="$tmp_json"
  fi

  set +e
  py_output=$(python3 - "$json_source" "$REQUIRED_CHECKS" << 'EOF'
import json
import sys

raw_input = sys.argv[1]
required_raw = sys.argv[2]
if "\n" in required_raw:
    raw_list = required_raw.split("\n")
elif "|" in required_raw:
    raw_list = required_raw.split("|")
elif ";" in required_raw:
    raw_list = required_raw.split(";")
else:
    raw_list = required_raw.split(",")
required_checks = [c.strip() for c in raw_list if c.strip()]

try:
    if raw_input.startswith('{') or raw_input.startswith('['):
        payload = json.loads(raw_input)
    else:
        with open(raw_input, 'r', encoding='utf-8') as f:
            payload = json.load(f)
except Exception as e:
    print(f"ERR_PARSE: {e}")
    sys.exit(2)

if isinstance(payload, dict) and "message" in payload and "check_runs" not in payload:
    print(f"ERR_API: {payload.get('message')}")
    sys.exit(3)

runs = payload.get("check_runs", [])
runs_by_name = {}
for run in sorted(runs, key=lambda r: r.get("id") or 0, reverse=True):
    name = run.get("name")
    if name and name not in runs_by_name:
        runs_by_name[name] = run

all_success = True
failed_checks = []
pending_checks = []
success_checks = []

for req in required_checks:
    if req not in runs_by_name:
        pending_checks.append((req, "missing"))
        all_success = False
    else:
        run = runs_by_name[req]
        status = (run.get("status") or "").lower()
        conclusion = (run.get("conclusion") or "").lower()
        if status != "completed":
            pending_checks.append((req, status or "in_progress"))
            all_success = False
        elif conclusion == "success":
            success_checks.append(req)
        else:
            failed_checks.append((req, conclusion or "unknown"))
            all_success = False

if failed_checks:
    for name, concl in failed_checks:
        print(f"FAILED:{name}:{concl}")
    sys.exit(10)
elif all_success:
    for name in success_checks:
        print(f"SUCCESS:{name}")
    sys.exit(0)
else:
    for name, st in pending_checks:
        print(f"PENDING:{name}:{st}")
    sys.exit(20)
EOF
)
  py_exit=$?
  set -e

  if [ "$is_temp_file" -eq 1 ]; then
    rm -f "$json_source"
  fi

  if [ "$py_exit" -eq 0 ]; then
    echo "All required CI checks passed for commit $COMMIT_SHA:"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      name="${line#SUCCESS:}"
      echo "  ✓ $name: success"
    done <<< "$py_output"
    exit 0
  elif [ "$py_exit" -eq 10 ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      rest="${line#FAILED:}"
      name="${rest%%:*}"
      concl="${rest#*:}"
      echo "::error::Required check '$name' failed with conclusion '$concl'. Release blocked."
    done <<< "$py_output"
    exit 1
  elif [ "$py_exit" -eq 20 ]; then
    if [ "$elapsed" -ge "$MAX_WAIT_SECONDS" ]; then
      echo "::error::Timed out after ${MAX_WAIT_SECONDS}s waiting for required CI checks to complete on commit $COMMIT_SHA."
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        rest="${line#PENDING:}"
        name="${rest%%:*}"
        st="${rest#*:}"
        echo "::error::Check '$name' was still in state '$st'."
      done <<< "$py_output"
      exit 1
    fi

    echo "Waiting for CI checks to complete... (${elapsed}s / ${MAX_WAIT_SECONDS}s elapsed)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      rest="${line#PENDING:}"
      name="${rest%%:*}"
      st="${rest#*:}"
      echo "  ⏳ $name: $st"
    done <<< "$py_output"

    sleep "$POLL_INTERVAL_SECONDS"
    iter=$((iter + 1))
  else
    echo "::warning::$py_output"
    if [ "$elapsed" -ge "$MAX_WAIT_SECONDS" ]; then
      echo "::error::Failed to verify CI checks for commit $COMMIT_SHA: $py_output"
      exit 1
    fi
    sleep "$POLL_INTERVAL_SECONDS"
    iter=$((iter + 1))
  fi
done
