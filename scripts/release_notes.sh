#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <from-ref> <to-ref>" >&2
  exit 1
fi

from_ref="$1"
to_ref="$2"
range="${from_ref}..${to_ref}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

print_section() {
  local title="$1"
  local content="$2"
  local prefix_newline="$3"
  local line=""
  if [[ -z "${content}" ]]; then
    return
  fi
  if [[ "${prefix_newline}" -eq 1 ]]; then
    printf "\n"
  fi
  printf "## **%s**\n" "${title}"
  while IFS= read -r line; do
    [[ -n "${line}" ]] && printf -- "- %s\n" "${line}"
  done <<< "${content}"
  return 0
}

features=""
fixes=""
other=""
feat_re='^[Ff][Ee][Aa][Tt](\([^)]+\))?:[[:space:]]+(.+)$'
fix_re='^[Ff][Ii][Xx](\([^)]+\))?:[[:space:]]+(.+)$'

while IFS= read -r subject || [[ -n "${subject}" ]]; do
  if [[ "${subject}" =~ ${feat_re} ]]; then
    features+="${BASH_REMATCH[2]}"$'\n'
  elif [[ "${subject}" =~ ${fix_re} ]]; then
    fixes+="${BASH_REMATCH[2]}"$'\n'
  elif [[ -n "${subject}" ]]; then
    other+="${subject}"$'\n'
  fi
done < <(git log --no-merges --reverse --pretty=format:%s "${range}")

printed=0
if [[ -n "${features}" ]]; then
  print_section "Features" "${features}" 0
  printed=1
fi

if [[ -n "${fixes}" ]]; then
  print_section "Fixes" "${fixes}" "${printed}"
  printed=1
fi

if [[ -n "${other}" ]]; then
  print_section "Other" "${other}" "${printed}"
fi
