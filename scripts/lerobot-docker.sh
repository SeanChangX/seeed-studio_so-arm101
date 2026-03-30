#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml")
GPU_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.gpu.yml")

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_MAGENTA="$(tput setaf 5)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_MAGENTA=""
  C_CYAN=""
fi

print_box() {
  local color="$1"
  shift
  local lines=("$@")
  local max_len=0
  local line=""

  for line in "${lines[@]}"; do
    if (( ${#line} > max_len )); then
      max_len=${#line}
    fi
  done

  local border
  border="+$(printf '%*s' "$((max_len + 2))" '' | tr ' ' '-')+"

  printf "%b%s%b\n" "${C_BOLD}${color}" "${border}" "${C_RESET}"
  for line in "${lines[@]}"; do
    printf "%b| %-${max_len}s |%b\n" "${C_BOLD}${color}" "${line}" "${C_RESET}"
  done
  printf "%b%s%b\n" "${C_BOLD}${color}" "${border}" "${C_RESET}"
}

info() {
  printf "%b[%s]%b %s\n" "${C_CYAN}${C_BOLD}" "INFO" "${C_RESET}" "$1"
}

success() {
  printf "%b[%s]%b %s\n" "${C_GREEN}${C_BOLD}" " OK " "${C_RESET}" "$1"
}

warn() {
  printf "%b[%s]%b %s\n" "${C_YELLOW}${C_BOLD}" "WARN" "${C_RESET}" "$1"
}

error() {
  printf "%b[%s]%b %s\n" "${C_RED}${C_BOLD}" "ERR " "${C_RESET}" "$1" >&2
}

usage() {
  print_box "${C_MAGENTA}" \
    "LeRobot Docker Launcher" \
    "" \
    "Usage:" \
    "  ./scripts/lerobot-docker.sh build [cpu|gpu]" \
    "  ./scripts/lerobot-docker.sh up [cpu|gpu]" \
    "  ./scripts/lerobot-docker.sh shell [cpu|gpu]" \
    "  ./scripts/lerobot-docker.sh down" \
    "  ./scripts/lerobot-docker.sh logs"
}

select_compose() {
  local profile="${1:-cpu}"
  if [[ "${profile}" == "gpu" ]]; then
    echo "gpu"
  elif [[ "${profile}" == "cpu" ]]; then
    echo "cpu"
  else
    error "Unsupported profile: ${profile}"
    exit 1
  fi
}

compose_run() {
  local mode="$1"
  shift
  if [[ "${mode}" == "gpu" ]]; then
    docker compose "${GPU_COMPOSE[@]}" "$@"
  else
    docker compose "${BASE_COMPOSE[@]}" "$@"
  fi
}

ensure_dirs() {
  mkdir -p "${ROOT_DIR}/workspace" "${ROOT_DIR}/cache/hf" "${ROOT_DIR}/cache/torch" "${ROOT_DIR}/cache/triton"
}

cmd="${1:-}"
profile="${2:-cpu}"

case "${cmd}" in
  build)
    mode="$(select_compose "${profile}")"
    print_box "${C_BLUE}" "Build image" "profile: ${mode}" "project: ${ROOT_DIR}"
    ensure_dirs
    compose_run "${mode}" build
    success "Build completed (${mode})"
    ;;
  up)
    mode="$(select_compose "${profile}")"
    print_box "${C_BLUE}" "Start container" "profile: ${mode}" "mode: detached"
    ensure_dirs
    compose_run "${mode}" up -d
    success "Container started (${mode})"
    ;;
  shell)
    mode="$(select_compose "${profile}")"
    print_box "${C_BLUE}" "Open shell" "profile: ${mode}" "container: lerobot"
    ensure_dirs
    compose_run "${mode}" up -d
    info "Launching interactive shell with TERM=${TERM:-xterm-256color}"
    compose_run "${mode}" exec -e TERM="${TERM:-xterm-256color}" -e COLORTERM=truecolor lerobot /bin/bash -i
    ;;
  down)
    warn "Stopping container"
    docker compose "${BASE_COMPOSE[@]}" down
    success "Container stopped"
    ;;
  logs)
    info "Streaming logs"
    docker compose "${BASE_COMPOSE[@]}" logs -f --tail=200
    ;;
  *)
    usage
    exit 1
    ;;
esac
