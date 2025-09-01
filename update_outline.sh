#!/usr/bin/bash
set -euo pipefail

STATE_DIR="/opt/outline/persisted-state"
START_SCRIPT="${STATE_DIR}/start_container.sh"

# ---- Pretty output (цвета корректные) ---------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'
  OK="${GREEN}✔${RESET}"; FAIL="${RED}✘${RESET}"; INFO="${BLUE}ℹ${RESET}"
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
  OK="[OK]"; FAIL="[ERR]"; INFO="[i]"
fi

msg()   { echo -e "$@"; }
info()  { msg "${INFO} $*"; }
ok()    { msg "${OK} $*"; }
warn()  { msg "${YELLOW}!${RESET} $*"; }
err()   { msg "${FAIL} $*" >&2; }

usage() {
  cat <<USAGE
${BOLD}Usage:${RESET} ${0##*/} [-i REPO] [-t TAG]
  -i REPO   указать репозиторий (по умолчанию — как в start_container.sh)
  -t TAG    указать тег (по умолчанию: latest)

${BOLD}Examples:${RESET}
  ${0##*/}                    # обновить текущий репозиторий до :latest
  ${0##*/} -t 1.9.421         # текущий репозиторий до :1.9.421
  ${0##*/} -i lobzikfase2/shadowgodbox -t 1.9.421
USAGE
}


repo_override=""
tag="latest"
while getopts ":i:t:h" opt; do
  case "$opt" in
    i) repo_override="$OPTARG" ;;
    t) tag="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) err "Unknown option: -$OPTARG"; usage; exit 2 ;;
    :)  err "Option -$OPTARG requires an argument"; usage; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  err "ROOT PRIVILEGES REQUIRED! Run with sudo."
  exit 1
fi

[[ -r "$START_SCRIPT" ]] || { err "Not found: $START_SCRIPT"; exit 1; }

# ---- Parse current image & container name -----------------------------------
current_image="$(awk '
  /# The Outline server image to run\./ {getline; gsub(/^[[:space:]]*|"|[[:space:]]*$/,""); print; exit}
' "$START_SCRIPT")"
[[ -n "$current_image" ]] || { err "Cannot parse image from $START_SCRIPT"; exit 1; }

img_no_digest="${current_image%@*}"
if [[ "${img_no_digest##*/}" == *:* ]]; then
  current_repo="${img_no_digest%:*}"
else
  current_repo="$img_no_digest"
fi

repo="${repo_override:-$current_repo}"
new_image="${repo}:${tag}"

container_name="$(awk '
  /docker_command=\(/,/\)/ {
    for (i=1;i<=NF;i++) if ($i=="--name") {print $(i+1); exit}
  }' "$START_SCRIPT" | sed 's/^"//; s/"$//')"
container_name="${container_name:-shadowbox}"

# ---- Helper: read version locally -----------------------------------
get_version() {
  [[ -r /opt/outline/access.txt ]] || return 1
  eval "$(sed -n 's/^apiUrl:https:\/\/[^:]*:\([0-9]*\)\/\(.*\)/PORT=\1 PASS=\2/p' /opt/outline/access.txt)"
  [[ -n "${PORT:-}" && -n "${PASS:-}" ]] || return 1
  curl -sS -4k "https://127.0.0.1:${PORT}/${PASS}/server" \
    | grep -o '"version":"[^"]*"' | cut -d'"' -f4
}

# ---- Show current server version (if running) --------------------------------
if docker ps --format '{{.Names}}' | grep -Fxq "$container_name"; then
  if cur_ver="$(get_version 2>/dev/null)"; then
    msg "${CYAN}${BOLD}Current server version:${RESET} ${BOLD}$cur_ver${RESET}"
  else
    warn "Current server version: unavailable (API not ready or access.txt missing)"
  fi
else
  warn "Container '${container_name}' is not running. Skipping current version check."
fi

# ---- Plan & pull -------------------------------------------------------------
msg "${BOLD}Update plan:${RESET}"
msg "  ${DIM}from${RESET} ${current_image}"
msg "    ${DIM}to${RESET} ${new_image}"
info "Pulling image ${new_image} ..."
docker pull "$new_image" >/dev/null
ok "Image pulled"

# ---- Patch start script & restart -------------------------------------------
info "Updating image line in ${START_SCRIPT}"
sed -i -E '/# The Outline server image to run\./{n;s|^  ".*"$|  "'"$new_image"'"|}' "$START_SCRIPT"
ok "Start script updated"

info "Restarting via start script"
"$START_SCRIPT" >/dev/null
ok "Container '${container_name}' restarted"

# ---- Show new server version -------------------------------------------------
for _ in 1 2 3 4 5; do
  if new_ver="$(get_version 2>/dev/null)"; then
    msg "${GREEN}${BOLD}New server version:${RESET} ${BOLD}$new_ver${RESET}"
    ok "Update succeeded"
    exit 0
  fi
  sleep 1
done

warn "New server version: unavailable yet (API may still be starting)"
exit 0
