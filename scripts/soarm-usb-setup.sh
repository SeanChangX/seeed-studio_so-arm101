#!/usr/bin/env bash
set -euo pipefail

UNPLUG_TIMEOUT="${UNPLUG_TIMEOUT:-30}"
PLUG_TIMEOUT="${PLUG_TIMEOUT:-60}"
SOARM_USB_ASSUME_ALL="${SOARM_USB_ASSUME_ALL:-0}"
CHOSEN_PORTS=()

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""
  C_BOLD=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
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

list_serial_ports() {
  local p
  shopt -s nullglob
  for p in /dev/ttyACM* /dev/ttyUSB*; do
    printf "%s\n" "${p}"
  done
  shopt -u nullglob
}

ports_signature() {
  list_serial_ports | sort -u | tr '\n' ' '
}

print_ports() {
  local title="$1"
  mapfile -t ports < <(list_serial_ports | sort -u)
  printf "%b%s%b\n" "${C_BOLD}" "${title}" "${C_RESET}"
  if [[ "${#ports[@]}" -eq 0 ]]; then
    printf "  (none)\n"
    return
  fi
  printf "  %s\n" "${ports[@]}"
}

pick_new_ports() {
  local baseline_ports="$1"
  local timeout="$2"
  local settle_after_first="${DETECT_SETTLE_SECONDS:-4}"
  local waited=0
  local current_ports=""
  local detected_ports=""
  local collected_ports=""
  local first_detected=0
  local stable_secs=0
  local last_snapshot=""
  local progress_printed=0

  while (( waited < timeout )); do
    if (( first_detected == 0 )); then
      printf "\r[INFO] Waiting for first new device... %2ds/%2ds" "${waited}" "${timeout}" >&2
      progress_printed=1
    fi

    current_ports="$(list_serial_ports | sort -u || true)"
    detected_ports="$(comm -13 <(printf "%s\n" "${baseline_ports}") <(printf "%s\n" "${current_ports}") || true)"
    if [[ -n "${detected_ports}" ]]; then
      collected_ports="$(printf "%s\n%s\n" "${collected_ports}" "${detected_ports}" | sed '/^$/d' | sort -u)"
      if (( first_detected == 0 )); then
        printf "\n[INFO] First new device detected. Collecting more for %ss...\n" "${settle_after_first}" >&2
      fi
      first_detected=1
    fi

    if (( first_detected == 1 )); then
      if [[ "${collected_ports}" == "${last_snapshot}" ]]; then
        stable_secs=$((stable_secs + 1))
      else
        last_snapshot="${collected_ports}"
        stable_secs=0
      fi

      printf "\r[INFO] Collecting additional devices... stable %ds/%ds" "${stable_secs}" "${settle_after_first}" >&2
      progress_printed=1

      if (( stable_secs >= settle_after_first )); then
        break
      fi
    fi

    sleep 1
    waited=$((waited + 1))
  done

  if (( progress_printed == 1 )); then
    printf "\n" >&2
  fi

  if [[ -n "${collected_ports}" ]]; then
    printf "%s\n" "${collected_ports}"
    return 0
  fi

  return 1
}

choose_ports() {
  local -a candidates=("$@")
  local choice=""
  local idx=""
  local max=""

  CHOSEN_PORTS=()

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    CHOSEN_PORTS=("${candidates[0]}")
    return 0
  fi

  warn "Multiple new serial devices detected:"
  printf "  %s\n" "${candidates[@]}"

  if [[ "${SOARM_USB_ASSUME_ALL}" == "1" ]]; then
    info "SOARM_USB_ASSUME_ALL=1, auto-select all detected devices."
    CHOSEN_PORTS=("${candidates[@]}")
    return 0
  fi

  printf "Apply permission to all new devices? [Y/n] "
  read -r choice < /dev/tty
  case "${choice}" in
    n|N|no|NO)
      max="${#candidates[@]}"
      while true; do
        printf "Select SO-ARM tty [1-%s]: " "${max}"
        read -r idx < /dev/tty
        if [[ "${idx}" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= max )); then
          CHOSEN_PORTS=("${candidates[$((idx - 1))]}")
          return 0
        fi
        warn "Invalid selection, choose a number from 1 to ${max}."
      done
      ;;
    *)
      CHOSEN_PORTS=("${candidates[@]}")
      return 0
      ;;
  esac
}

apply_permissions() {
  local port="$1"
  info "Applying write permission: chmod 666 ${port}"
  if [[ "${EUID}" -eq 0 ]]; then
    chmod 666 "${port}"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo chmod 666 "${port}"
    return 0
  fi

  error "sudo is not available, cannot change permissions as non-root user."
  return 1
}

main() {
  local initial_ports=""
  local after_unplug=""
  local baseline_ports=""
  local -a initial_ports_array=()
  local -a detected_ports=()
  local -a new_ports_array=()
  local -a chosen_ports=()
  local port=""

  print_box "${C_BLUE}" \
    "SO-ARM USB Setup" \
    "Detect tty devices by replug flow" \
    "Apply chmod 666 automatically"

  initial_ports="$(ports_signature)"
  mapfile -t initial_ports_array < <(list_serial_ports | sort -u)
  print_ports "Current serial devices:"

  if [[ "${#initial_ports_array[@]}" -eq 0 ]]; then
    info "No existing serial devices found. Skipping unplug step."
    baseline_ports=""
    print_ports "Baseline devices:"
  else
    read -r -p "Step 1/2: Unplug SO-ARM USB now, then press Enter to continue..."
    info "Waiting up to ${UNPLUG_TIMEOUT}s for unplug state to settle..."
    sleep 1
    after_unplug="$(ports_signature)"
    if [[ "${after_unplug}" == "${initial_ports}" ]]; then
      warn "No serial change detected after unplug step. Continuing anyway."
    fi
    baseline_ports="$(list_serial_ports | sort -u)"
    print_ports "Baseline devices after unplug step:"
  fi

  read -r -p "Step 2/2: Plug all SO-ARM USB devices now, then press Enter to detect once..."
  info "Detecting new serial devices (settle window: ${DETECT_SETTLE_SECONDS:-4}s)"
  mapfile -t new_ports_array < <(pick_new_ports "${baseline_ports}" "${PLUG_TIMEOUT}" || true)
  if [[ "${#new_ports_array[@]}" -eq 0 ]]; then
    error "No new /dev/ttyACM* or /dev/ttyUSB* detected within ${PLUG_TIMEOUT}s."
    exit 1
  fi

  info "Detected ${#new_ports_array[@]} new serial device(s)."
  printf "  %s\n" "${new_ports_array[@]}"

  choose_ports "${new_ports_array[@]}"
  chosen_ports=("${CHOSEN_PORTS[@]}")
  if [[ "${#chosen_ports[@]}" -eq 0 ]]; then
    error "No tty selected from detected ports."
    exit 1
  fi

  for port in "${chosen_ports[@]}"; do
    info "Detected SO-ARM device: ${port}"
    apply_permissions "${port}"
    detected_ports+=("${port}")
  done

  print_ports "Current serial devices:"

  if [[ "${#detected_ports[@]}" -eq 0 ]]; then
    warn "No SO-ARM serial port registered."
    exit 1
  fi

  success "Completed. Registered SO-ARM tty devices:"
  printf "  %s\n" "${detected_ports[@]}"
}

main "$@"
