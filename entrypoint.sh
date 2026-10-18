#!/usr/bin/env bash
# Registers one ephemeral runner to GH_OWNER/GH_REPO, runs a single job, exits.
# Env: GH_OWNER, GH_REPO, GH_PAT (required); RUNNER_NAME, RUNNER_LABELS (optional).
# Exits non-zero if required env is missing or the registration token request fails.
set -euo pipefail

: "${GH_OWNER:?GH_OWNER is required}"
: "${GH_REPO:?GH_REPO is required}"
: "${GH_PAT:?GH_PAT is required}"
RUNNER_NAME="${RUNNER_NAME:-runner-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-ephemeral}"

cd /home/runner
# Docker restarts keep the writable layer: stale registration makes config.sh refuse to run, and _work/_diag carry over the previous job.
# No `config.sh remove`: GitHub already deregistered the ephemeral runner, and remove would need another token.
rm -rf .runner .credentials .credentials_rsaparams .setup_info _work _diag

# Header goes via stdin so the PAT never appears in curl's argv (/proc/*/cmdline).
reg_token="$(
  printf 'Authorization: Bearer %s\n' "$GH_PAT" |
    curl -fsS -X POST \
      -H @- \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token" |
    jq -r '.token'
)" || reg_token=""
unset GH_PAT

if [[ -z "$reg_token" || "$reg_token" == "null" ]]; then
  echo "ERROR: failed to get registration token for ${GH_OWNER}/${GH_REPO} (check PAT scope/expiry)" >&2
  exit 1
fi

./config.sh --unattended \
  --url "https://github.com/${GH_OWNER}/${GH_REPO}" \
  --token "$reg_token" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --ephemeral \
  --replace \
  --disableupdate
unset reg_token

exec ./run.sh
