#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly archived_prototype_ref="mxpszppootpltifzvjla"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required remote foundation prerequisite: %s\n' "$command_name" >&2
    exit 127
  fi
}

require_value() {
  local variable_name="$1"
  local value="${!variable_name:-}"
  if [[ -z "$value" ]]; then
    printf 'Missing required non-production project variable: %s\n' "$variable_name" >&2
    exit 64
  fi
}

if [[ "${REMOTE_FOUNDATION_CONFIRM:-}" != "nonproduction-only" ]]; then
  printf 'Remote foundation verification requires REMOTE_FOUNDATION_CONFIRM=nonproduction-only.\n' >&2
  exit 64
fi

for command_name in supabase tr; do
  require_command "$command_name"
done

profile_args=()
if [[ -n "${SUPABASE_PROFILE:-}" ]]; then
  profile_args=(--profile "$SUPABASE_PROFILE")
fi

require_value SAVARI_NONPROD_PROJECT_REF
require_value DASTAK_NONPROD_PROJECT_REF

if [[ "$SAVARI_NONPROD_PROJECT_REF" == "$DASTAK_NONPROD_PROJECT_REF" ]]; then
  printf 'Savari and Dastak must use different non-production project refs.\n' >&2
  exit 64
fi

for project_ref in "$SAVARI_NONPROD_PROJECT_REF" "$DASTAK_NONPROD_PROJECT_REF"; do
  if [[ "$project_ref" == "$archived_prototype_ref" ]]; then
    printf 'The archived prototype project cannot be used for foundation verification.\n' >&2
    exit 64
  fi
done

expected_project_ref() {
  local backend="$1"
  case "$backend" in
    Savari) printf '%s' "$SAVARI_NONPROD_PROJECT_REF" ;;
    Dastak) printf '%s' "$DASTAK_NONPROD_PROJECT_REF" ;;
  esac
}

verify_backend() {
  local backend="$1"
  local backend_root="$repo_root/Backends/$backend"
  local project_ref_path="$backend_root/supabase/.temp/project-ref"
  local expected_ref
  local linked_ref

  expected_ref="$(expected_project_ref "$backend")"
  if [[ ! -f "$project_ref_path" ]]; then
    printf '%s is not linked. Link it to its approved non-production project before verification.\n' "$backend" >&2
    exit 1
  fi

  linked_ref="$(tr -d '[:space:]' < "$project_ref_path")"
  if [[ "$linked_ref" != "$expected_ref" ]]; then
    printf '%s is linked to an unexpected project; refusing remote verification.\n' "$backend" >&2
    exit 1
  fi

  printf 'Verifying %s linked non-production database.\n' "$backend"
  cd "$backend_root"
  supabase db lint --linked --fail-on error --schema public,private,audit "${profile_args[@]}"
  "$repo_root/scripts/test-backend-security.sh" "$backend" --linked
}

for backend in Savari Dastak; do
  verify_backend "$backend"
done

printf 'Both linked non-production database security gates passed.\n'
