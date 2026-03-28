#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml")
GPU_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.gpu.yml")

usage() {
  cat <<'EOF'
Usage:
  ./scripts/lerobot-docker.sh up [cpu|gpu]
  ./scripts/lerobot-docker.sh shell [cpu|gpu]
  ./scripts/lerobot-docker.sh down
  ./scripts/lerobot-docker.sh logs
EOF
}

select_compose() {
  local profile="${1:-cpu}"
  if [[ "${profile}" == "gpu" ]]; then
    echo "gpu"
  elif [[ "${profile}" == "cpu" ]]; then
    echo "cpu"
  else
    echo "Unsupported profile: ${profile}" >&2
    exit 1
  fi
}

cmd="${1:-}"
profile="${2:-cpu}"

case "${cmd}" in
  up)
    mode="$(select_compose "${profile}")"
    mkdir -p "${ROOT_DIR}/workspace" "${ROOT_DIR}/cache/hf" "${ROOT_DIR}/cache/torch" "${ROOT_DIR}/cache/triton"
    if [[ "${mode}" == "gpu" ]]; then
      docker compose "${GPU_COMPOSE[@]}" up -d --build
    else
      docker compose "${BASE_COMPOSE[@]}" up -d --build
    fi
    ;;
  shell)
    mode="$(select_compose "${profile}")"
    mkdir -p "${ROOT_DIR}/workspace" "${ROOT_DIR}/cache/hf" "${ROOT_DIR}/cache/torch" "${ROOT_DIR}/cache/triton"
    if [[ "${mode}" == "gpu" ]]; then
      docker compose "${GPU_COMPOSE[@]}" up -d --build
      docker compose "${GPU_COMPOSE[@]}" exec lerobot /bin/bash
    else
      docker compose "${BASE_COMPOSE[@]}" up -d --build
      docker compose "${BASE_COMPOSE[@]}" exec lerobot /bin/bash
    fi
    ;;
  down)
    docker compose "${BASE_COMPOSE[@]}" down
    ;;
  logs)
    docker compose "${BASE_COMPOSE[@]}" logs -f --tail=200
    ;;
  *)
    usage
    exit 1
    ;;
esac
