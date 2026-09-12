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

for command_name in curl vercel rg rsync; do
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
      production_url="https://dastak-customer.vercel.app"
      ;;
    delivery)
      project="dastak-delivery"
      project_id="prj_NvUua79V8pUlGGA4QIOixsVFJDsX"
      expected_variant="dastak-delivery"
      production_url="https://dastak-delivery.vercel.app"
      ;;
    merchant)
      project="dastak-merchant"
      project_id="prj_O1XldqBxHKKVChvBqOASbBvi7Tyl"
      expected_variant="dastak-merchant"
      production_url="https://dastak-merchant.vercel.app"
      ;;
    admin)
      project="dastak-admin"
      project_id="prj_8bTPMpvbQqSOqcgXWwR8cHp0shVS"
      expected_variant="dastak-admin"
      production_url="https://dastak-admin.vercel.app"
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

commit_sha="$(git -C "$repo_root" rev-parse HEAD)"
deploy_args=(deploy "$deploy_root" --project "$project" --scope "$team_slug" --archive=tgz --yes)
deploy_args+=(--meta "gitCommitSha=$commit_sha" --build-env "GIT_COMMIT_SHA=$commit_sha")
if [[ "$mode" == "--production" || "$mode" == "--staged-production" ]]; then
  deploy_args+=(--prod)
fi
if [[ "$mode" == "--staged-production" ]]; then
  # Build with production configuration without switching traffic before a
  # coordinated native/backend rollout. Promote this exact artifact afterwards.
  deploy_args+=(--skip-domain)
fi
deployment_output="$(VERCEL_ORG_ID="$org_id" VERCEL_PROJECT_ID="$project_id" vercel "${deploy_args[@]}" 2>&1)"
printf '%s\n' "$deployment_output"
deployment_url="$(rg -o 'https://[^[:space:]]+\.vercel\.app' <<<"$deployment_output" | tail -1)"
if [[ -z "$deployment_url" ]]; then
  printf 'Could not resolve the deployment URL for provenance verification.\n' >&2
  exit 1
fi

verification_url="$deployment_url"
if [[ "$mode" == "--production" ]]; then
  verification_url="$production_url"
fi
verified=false
for _attempt in {1..20}; do
  html_file="$audit_root/release.html"
  headers_file="$audit_root/release.headers"
  if curl --fail --silent --show-error --location --dump-header "$headers_file" "$verification_url" -o "$html_file"; then
    actual_sha="$(sed -n 's/.*name="dastak:git-sha" content="\([^"]*\)".*/\1/p' "$html_file" | head -1)"
    actual_variant="$(sed -n 's/.*name="dastak:variant" content="\([^"]*\)".*/\1/p' "$html_file" | head -1)"
    actual_environment="$(sed -n 's/.*name="dastak:environment" content="\([^"]*\)".*/\1/p' "$html_file" | head -1)"
    actual_deployment_id="$(sed -n 's/.*name="dastak:deployment-id" content="\([^"]*\)".*/\1/p' "$html_file" | head -1)"
    expected_environment="preview"
    if [[ "$mode" == "--production" || "$mode" == "--staged-production" ]]; then
      expected_environment="production"
    fi
    if [[ "$actual_sha" == "$commit_sha" &&
      "$actual_variant" == "$expected_variant" &&
      "$actual_environment" == "$expected_environment" &&
      -n "$actual_deployment_id" && "$actual_deployment_id" != "local" ]] &&
      rg -qi '^content-security-policy:.*frame-ancestors .none.' "$headers_file" &&
      rg -qi '^x-content-type-options:[[:space:]]*nosniff' "$headers_file"; then
      verified=true
      break
    fi
  fi
  sleep 2
done
if [[ "$verified" != true ]]; then
  printf 'Deployment provenance/header verification failed for %s (expected %s / %s / %s).\n' \
    "$verification_url" "$expected_variant" "$commit_sha" "$expected_environment" >&2
  exit 1
fi
printf '%s deployment provenance verified: sha=%s variant=%s environment=%s deployment=%s url=%s\n' \
  "$requested_role" "$commit_sha" "$expected_variant" "$actual_environment" "$actual_deployment_id" "$verification_url"
