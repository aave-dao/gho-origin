#!/usr/bin/env bash
# Fails if a workflow that runs on pull requests is not covered by manual-pr-ci.yml, either as a
# called workflow (`uses: ./.github/workflows/<file>`) or as one whose jobs it mirrors inline.
set -euo pipefail

WORKFLOWS_DIR=".github/workflows"
MANUAL="${WORKFLOWS_DIR}/manual-pr-ci.yml"

# Jobs mirrored inline in manual-pr-ci.yml, because the shared workflows they call take no ref input.
MIRRORED=("test.yml")
# Workflows that need no manual counterpart.
EXEMPT=("manual-pr-ci.yml" "manual-pr-ci-guard.yml")

contains() {
  local needle="$1"
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

called="$(yq -r '.jobs[].uses // "" | select(test("^\./\.github/workflows/")) | sub("^\./\.github/workflows/"; "")' "$MANUAL")"

missing=()
for file in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
  [[ -e "$file" ]] || continue
  name="$(basename "$file")"
  contains "$name" "${EXEMPT[@]}" && continue

  events="$(yq -r '(.on | select(tag == "!!map") | keys | .[]), (.on | select(tag == "!!seq") | .[]), (.on | select(tag == "!!str"))' "$file")"
  grep -qxE 'pull_request|pull_request_target' <<< "$events" || continue

  if contains "$name" "${MIRRORED[@]}" || grep -qxF "$name" <<< "$called"; then
    echo "ok       ${name}"
  else
    echo "missing  ${name}"
    missing+=("$name")
  fi
done

if (( ${#missing[@]} )); then
  echo "::error::Add these PR workflows to ${MANUAL} (call them, or mirror their jobs and list them in MIRRORED): ${missing[*]}"
  exit 1
fi
