#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s customer|delivery|merchant|admin|all --check|--preview|--staged-production|--production\n' "$0" >&2
  exit 64
}

role="${1:-}"
mode="${2:-}"
[[ -n "$role" && -n "$mode" ]] || usage
case "$mode" in
  --check|--preview|--staged-production|--production) ;;
  *) usage ;;
esac
if [[ "$role" == "all" && "$mode" != "--check" ]]; then
  printf 'The all role is check-only; deploy one role at a time.\n' >&2
  exit 64
fi

for command_name in vercel rg rsync; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required deployment prerequisite: %s\n' "$command_name" >&2
    exit 127
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
team_slug="liquiflows-projects"
org_id="team_xna4AS3Xdk5s9jABGmtsRZ4K"
audit_root="$(mktemp -d "${TMPDIR:-/tmp}/dastak-vercel.XXXXXX")"

cleanup() {
  find "$audit_root" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

configure_role() {
  case "$1" in
    customer)
      project="dastak"
      project_id="prj_Wy48d7Vv3OXLAgulBukYHoXiXy0f"
      expected_variant="dastak-customer"
      ;;
    delivery)
      project="dastak-delivery"
      project_id="prj_NvUua79V8pUlGGA4QIOixsVFJDsX"
      expected_variant="dastak-delivery"
      ;;
    merchant)
      project="dastak-merchant"
      project_id="prj_O1XldqBxHKKVChvBqOASbBvi7Tyl"
      expected_variant="dastak-merchant"
      ;;
    admin)
      project="dastak-admin"
      project_id="prj_8bTPMpvbQqSOqcgXWwR8cHp0shVS"
      expected_variant="dastak-admin"
      ;;
    *) usage ;;
  esac
}

read_env_value() {
  local key="$1"
  local file="$2"
  local value
  value="$(sed -n "s/^${key}=//p" "$file" | tail -1)"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

check_role() {
  local requested_role="$1"
  local env_file inspect_output actual_variant
  configure_role "$requested_role"

  inspect_output="$(vercel project inspect "$project" --yes --scope "$team_slug" --no-color 2>&1)"
  if ! rg -q 'Root Directory[[:space:]]+Web/MarketplaceWeb' <<<"$inspect_output"; then
    printf '%s is not rooted at Web/MarketplaceWeb. Deployment stopped.\n' "$project" >&2
    exit 1
  fi

  env_file="$audit_root/$requested_role.env"
  VERCEL_ORG_ID="$org_id" VERCEL_PROJECT_ID="$project_id" \
    vercel env pull "$env_file" --environment=production --yes >/dev/null
  actual_variant="$(read_env_value VITE_APP_VARIANT "$env_file")"
  if [[ "$actual_variant" != "$expected_variant" ]]; then
    printf '%s expects %s but production contains %s. Deployment stopped.\n' \
      "$project" "$expected_variant" "${actual_variant:-no VITE_APP_VARIANT}" >&2
    exit 1
  fi
  for required_key in VITE_SUPABASE_URL VITE_SUPABASE_PUBLISHABLE_KEY; do
    if [[ -z "$(read_env_value "$required_key" "$env_file")" ]]; then
      printf '%s is missing %s. Deployment stopped.\n' "$project" "$required_key" >&2
      exit 1
    fi
  done
  printf '%-9s project=%-16s variant=%s verified\n' "$requested_role" "$project" "$expected_variant"
}

if [[ "$role" == "all" ]]; then
  for requested_role in customer delivery merchant admin; do
    check_role "$requested_role"
  done
  exit 0
fi

check_role "$role"
if [[ "$mode" == "--check" ]]; then
  exit 0
fi

deploy_root="$audit_root/deploy"
mkdir -p "$deploy_root/Web/MarketplaceWeb"
rsync -a \
  --exclude node_modules \
  --exclude dist \
  "$repo_root/Web/MarketplaceWeb/" \
  "$deploy_root/Web/MarketplaceWeb/"

deploy_args=(deploy "$deploy_root" --project "$project" --scope "$team_slug" --archive=tgz --yes)
deploy_args+=(--meta "gitCommitSha=$(git -C "$repo_root" rev-parse HEAD)")
if [[ "$mode" == "--production" || "$mode" == "--staged-production" ]]; then
  deploy_args+=(--prod)
fi
if [[ "$mode" == "--staged-production" ]]; then
  # Build with production configuration without switching traffic before a
  # coordinated native/backend rollout. Promote this exact artifact afterwards.
  deploy_args+=(--skip-domain)
fi
VERCEL_ORG_ID="$org_id" VERCEL_PROJECT_ID="$project_id" vercel "${deploy_args[@]}"
