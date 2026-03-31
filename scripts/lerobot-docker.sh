#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml")
GPU_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.gpu.yml")
HUMBLE_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.humble.yml")
HUMBLE_GPU_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.humble-gpu.yml")

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_MAGENTA="$(tput setaf 5)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""
  C_BOLD=""
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
    "SO-ARM Command Deck" \
    "" \
    "This launcher uses Command Deck mode." \
    "Run without arguments:" \
    "  ./scripts/lerobot-docker.sh"
}

is_interactive_terminal() {
  [[ -t 0 && -t 1 ]]
}

compose_run() {
  local mode="$1"
  shift
  case "${mode}" in
    gpu)
      docker compose "${GPU_COMPOSE[@]}" "$@"
      ;;
    humble)
      docker compose "${HUMBLE_COMPOSE[@]}" "$@"
      ;;
    humble-gpu)
      docker compose "${HUMBLE_GPU_COMPOSE[@]}" "$@"
      ;;
    *)
      docker compose "${BASE_COMPOSE[@]}" "$@"
      ;;
  esac
}

ensure_dirs() {
  mkdir -p \
    "${ROOT_DIR}/workspace" \
    "${ROOT_DIR}/workspace/ros2_ws/src" \
    "${ROOT_DIR}/cache/hf" \
    "${ROOT_DIR}/cache/torch" \
    "${ROOT_DIR}/cache/triton"
}

ensure_humble_mode() {
  local mode="$1"
  case "${mode}" in
    humble|humble-gpu) ;;
    *)
      error "ros2-setup only supports humble or humble-gpu profiles"
      exit 1
      ;;
  esac
}

ensure_xhost_access() {
  if [[ -z "${DISPLAY:-}" ]]; then
    warn "DISPLAY is not set; skipping xhost setup"
    return 0
  fi

  if ! command -v xhost >/dev/null 2>&1; then
    warn "xhost is not installed on host; GUI apps may not render"
    return 0
  fi

  if xhost +local:docker >/dev/null 2>&1; then
    success "X11 access enabled for local docker containers"
  else
    warn "xhost setup failed; GUI apps may not render"
  fi
}

run_build() {
  local mode="$1"
  print_box "${C_BLUE}" "Build image" "profile: ${mode}" "project: ${ROOT_DIR}"
  ensure_dirs
  compose_run "${mode}" build
  success "Build completed (${mode})"
}

default_image_tag_for_mode() {
  local mode="$1"
  case "${mode}" in
    gpu) echo "gpu" ;;
    humble) echo "humble" ;;
    humble-gpu) echo "humble-gpu" ;;
    *) echo "cpu" ;;
  esac
}

default_image_name() {
  echo "ghcr.io/seanchangx/seeed-studio_so-arm101"
}

default_fallback_image_name() {
  echo "seanchangx/seeed-lerobot"
}

image_ref_for_mode() {
  local mode="$1"
  local image_name="${IMAGE_NAME:-$(default_image_name)}"
  local image_tag="${IMAGE_TAG:-$(default_image_tag_for_mode "${mode}")}"
  printf "%s:%s" "${image_name}" "${image_tag}"
}

fallback_image_ref_for_mode() {
  local mode="$1"
  local fallback_name="${IMAGE_FALLBACK_NAME:-$(default_fallback_image_name)}"
  local image_tag="${IMAGE_TAG:-$(default_image_tag_for_mode "${mode}")}"
  if [[ -z "${fallback_name}" ]]; then
    return 1
  fi
  printf "%s:%s" "${fallback_name}" "${image_tag}"
}

image_exists_for_mode() {
  local mode="$1"
  local image_ref
  image_ref="$(image_ref_for_mode "${mode}")"
  docker image inspect "${image_ref}" >/dev/null 2>&1
}

pull_image_with_fallback_for_mode() {
  local mode="$1"
  local primary_ref=""
  local fallback_ref=""

  primary_ref="$(image_ref_for_mode "${mode}")"
  info "Trying to pull image: ${primary_ref}"
  if docker pull "${primary_ref}"; then
    success "Pulled image from primary registry: ${primary_ref}"
    return 0
  fi

  fallback_ref="$(fallback_image_ref_for_mode "${mode}" || true)"
  if [[ -z "${fallback_ref}" || "${fallback_ref}" == "${primary_ref}" ]]; then
    warn "Primary pull failed and no fallback image is configured."
    return 1
  fi

  warn "Primary pull failed, trying fallback image: ${fallback_ref}"
  if docker pull "${fallback_ref}"; then
    success "Pulled image from fallback registry: ${fallback_ref}"
    docker tag "${fallback_ref}" "${primary_ref}" || true
    return 0
  fi

  warn "Fallback pull also failed."
  return 1
}

run_up() {
  local mode="$1"
  print_box "${C_BLUE}" "Start container" "profile: ${mode}" "mode: detached"
  ensure_dirs
  ensure_xhost_access
  compose_run "${mode}" up -d
  success "Container started (${mode})"
}

run_shell() {
  local mode="$1"
  print_box "${C_BLUE}" "Open shell" "profile: ${mode}" "container: lerobot"
  ensure_dirs
  ensure_xhost_access
  compose_run "${mode}" up -d
  info "Launching interactive shell with TERM=${TERM:-xterm-256color}"
  compose_run "${mode}" exec -e TERM="${TERM:-xterm-256color}" -e COLORTERM=truecolor lerobot /bin/bash -i
}

run_down() {
  local mode="$1"
  warn "Stopping container"
  compose_run "${mode}" down
  success "Container stopped (${mode})"
}

run_logs() {
  local mode="$1"
  info "Streaming logs"
  compose_run "${mode}" logs -f --tail=200
}

ros2_setup() {
  local mode="$1"
  local repo_url="${SO101_ROS2_REPO_URL:-https://github.com/nimiCurtis/so101_ros2.git}"
  local ws_dir="/workspace/ros2_ws"
  local repo_dir="${ws_dir}/src/so101_ros2"
  local host_repo_dir="${ROOT_DIR}/workspace/ros2_ws/src/so101_ros2"
  local compat_patch="${ROOT_DIR}/scripts/patches/so101_ros2-compat.patch"
  local rosdep_skip="${ROSDEP_SKIP_KEYS:-topic_based_ros2_control_msgs}"

  ensure_humble_mode "${mode}"
  ensure_dirs
  print_box "${C_BLUE}" "Bootstrap so101_ros2" "profile: ${mode}" "workspace: ${ws_dir}"

  compose_run "${mode}" up -d

  info "Ensuring so101_ros2 sources exist"
  compose_run "${mode}" exec -T lerobot bash -lc "\
set -euo pipefail; \
mkdir -p '${ws_dir}/src'; \
if [ ! -d '${repo_dir}/.git' ]; then \
  git clone --recurse-submodules '${repo_url}' '${repo_dir}'; \
else \
  git -C '${repo_dir}' submodule update --init --recursive; \
fi"

  if [[ -f "${compat_patch}" && -d "${host_repo_dir}/.git" ]]; then
    info "Applying local compatibility patch for so101_ros2"
    if git -C "${host_repo_dir}" apply --check "${compat_patch}" >/dev/null 2>&1; then
      git -C "${host_repo_dir}" apply "${compat_patch}"
      success "Applied compatibility patch"
    elif git -C "${host_repo_dir}" apply -R --check "${compat_patch}" >/dev/null 2>&1; then
      info "Compatibility patch already applied"
    else
      warn "Compatibility patch does not apply cleanly; upstream may have changed."
      warn "Patch file: ${compat_patch}"
    fi
  fi

  info "Normalizing bridge parameter YAML keys (namespace-safe)"
  compose_run "${mode}" exec -T lerobot bash -lc "\
set -euo pipefail; \
for f in '${repo_dir}/so101_ros2_bridge/config/so101_leader_params.yaml' '${repo_dir}/so101_ros2_bridge/config/so101_follower_params.yaml'; do \
  [ -f \"\${f}\" ] || continue; \
  line_no=\$(awk 'NF && \$1 !~ /^#/ {print NR; exit}' \"\${f}\"); \
  [ -n \"\${line_no}\" ] || continue; \
  current=\$(sed -n \"\${line_no}p\" \"\${f}\" | tr -d '[:space:]'); \
  if [ \"\${current}\" != '/**:' ]; then \
    sed -i \"\${line_no}s|.*|/**:|\" \"\${f}\"; \
  fi; \
done"

  info "Installing ROS dependencies (with rosdep retry)"
  compose_run "${mode}" exec -T -u root lerobot bash -lc "\
set -eo pipefail; \
source /opt/ros/humble/setup.bash; \
cd '${ws_dir}'; \
apt-get update; \
for i in 1 2 3; do \
  if rosdep update; then break; fi; \
  if [ \"\${i}\" -eq 3 ]; then \
    echo 'rosdep update failed after 3 attempts' >&2; \
    exit 1; \
  fi; \
  sleep 5; \
done; \
rosdep install --from-paths src --ignore-src -r -y --skip-keys '${rosdep_skip}'"

  info "Building ROS2 workspace"
  compose_run "${mode}" exec -T lerobot bash -lc "\
set -eo pipefail; \
source /opt/ros/humble/setup.bash; \
cd '${ws_dir}'; \
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release"

  success "ROS2 workspace bootstrap completed (${mode})"
  info "Load workspace in shell: source /workspace/ros2_ws/install/local_setup.bash"
}

run_usb_serial_setup() {
  local helper="${ROOT_DIR}/scripts/soarm-usb-setup.sh"
  print_box "${C_BLUE}" "SO-ARM USB Setup" "Detect tty device via replug flow" "Apply chmod 666 automatically"

  if [[ ! -f "${helper}" ]]; then
    error "Helper script not found: ${helper}"
    return 1
  fi

  bash "${helper}"
}

ACTION_SELECTED=""
PROFILE_SELECTED=""
ACTIVE_PROFILE=""

is_humble_profile() {
  local mode="$1"
  [[ "${mode}" == "humble" || "${mode}" == "humble-gpu" ]]
}

prompt_action() {
  local options=()
  local selection=""
  local hint=""

  if is_humble_profile "${ACTIVE_PROFILE}"; then
    options=("quickstart" "build" "up" "shell" "ros2-setup" "soarm-usb-setup" "logs" "down" "switch-profile" "quit")
    hint="quickstart = build + ros2-setup + shell"
  else
    options=("quickstart" "build" "up" "shell" "soarm-usb-setup" "logs" "down" "switch-profile" "quit")
    hint="quickstart = build + shell (switch to humble/humble-gpu for ROS2 setup)"
  fi

  print_box "${C_BLUE}" \
    "SO-ARM Command Deck" \
    "Active profile: ${ACTIVE_PROFILE}" \
    "Choose an action" \
    "${hint}"

  PS3="Action> "
  select selection in "${options[@]}"; do
    case "${selection}" in
      quickstart|build|up|shell|ros2-setup|soarm-usb-setup|logs|down|switch-profile|quit)
        ACTION_SELECTED="${selection}"
        return 0
        ;;
      *)
        warn "Invalid selection, choose a number from the list"
        ;;
    esac
  done
}

prompt_profile() {
  local options=()
  local selection=""
  options=("cpu" "gpu" "humble" "humble-gpu")

  PS3="Profile> "
  select selection in "${options[@]}"; do
    case "${selection}" in
      cpu|gpu|humble|humble-gpu)
        PROFILE_SELECTED="${selection}"
        return 0
        ;;
      *)
        warn "Invalid profile, choose a number from the list"
        ;;
    esac
  done
}

set_active_profile() {
  prompt_profile
  ACTIVE_PROFILE="${PROFILE_SELECTED}"
  success "Active profile set to: ${ACTIVE_PROFILE}"
}

require_humble_profile() {
  if ! is_humble_profile "${ACTIVE_PROFILE}"; then
    error "This action requires humble or humble-gpu. Use switch-profile first."
    return 1
  fi
}

ask_continue() {
  local answer=""
  printf "Run another action? [Y/n] "
  read -r answer
  case "${answer}" in
    n|N|no|NO)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

run_command_deck_once() {
  local action=""

  prompt_action
  action="${ACTION_SELECTED}"

  case "${action}" in
    quit)
      warn "Exited Command Deck"
      exit 0
      ;;
    quickstart)
      if image_exists_for_mode "${ACTIVE_PROFILE}"; then
        info "Image already exists: $(image_ref_for_mode "${ACTIVE_PROFILE}")"
        info "Skip build in quickstart. Use action 'build' to rebuild."
      else
        info "Image not found locally, trying registry pull before build."
        if pull_image_with_fallback_for_mode "${ACTIVE_PROFILE}"; then
          success "Using pulled image for quickstart."
        else
          info "No pullable image found, running build first."
          run_build "${ACTIVE_PROFILE}"
        fi
      fi
      if is_humble_profile "${ACTIVE_PROFILE}"; then
        ros2_setup "${ACTIVE_PROFILE}"
      fi
      run_shell "${ACTIVE_PROFILE}"
      ;;
    ros2-setup)
      require_humble_profile || return 0
      ros2_setup "${ACTIVE_PROFILE}"
      ;;
    soarm-usb-setup)
      run_usb_serial_setup
      ;;
    build|up|shell|logs|down)
      case "${action}" in
        build) run_build "${ACTIVE_PROFILE}" ;;
        up) run_up "${ACTIVE_PROFILE}" ;;
        shell) run_shell "${ACTIVE_PROFILE}" ;;
        logs) run_logs "${ACTIVE_PROFILE}" ;;
        down) run_down "${ACTIVE_PROFILE}" ;;
      esac
      ;;
    switch-profile)
      set_active_profile
      ;;
  esac
}

if [[ "$#" -gt 0 ]]; then
  error "Command Deck mode only. Run without arguments."
  usage
  exit 1
fi

if ! is_interactive_terminal; then
  error "Interactive terminal required for Command Deck mode."
  usage
  exit 1
fi

print_box "${C_BLUE}" "SO-ARM Command Deck" "Choose your working profile (you can switch later)"
set_active_profile

while true; do
  run_command_deck_once
  if ! ask_continue; then
    success "Done"
    exit 0
  fi
done
