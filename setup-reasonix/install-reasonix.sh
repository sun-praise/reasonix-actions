#!/usr/bin/env bash

set -euo pipefail

REASONIX_INSTALL_DIR="${REASONIX_INSTALL_DIR:-${RUNNER_TOOL_CACHE:-$HOME/.cache}/reasonix/bin}"
REASONIX_VERSION="${REASONIX_VERSION:-1.17.13}"
REASONIX_INSTALL_SOURCE="${REASONIX_INSTALL_SOURCE:-sun-praise/deepseek-reasonix}"
REASONIX_INSTALL_ATTEMPTS="${REASONIX_INSTALL_ATTEMPTS:-3}"
REASONIX_ALLOW_PREINSTALLED="${REASONIX_ALLOW_PREINSTALLED:-false}"
REASONIX_MIN_VERSION="${REASONIX_MIN_VERSION:-}"

DEFAULT_REASONIX_BIN_DIR="$HOME/.reasonix/bin"
FALLBACK_REASONIX_BIN_DIR="${RUNNER_TOOL_CACHE:-$HOME/.cache}/reasonix/bin"

require_positive_integer() {
  local value="$1"
  local name="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    printf '%s must be a positive integer, got %s\n' "$name" "$value" >&2
    exit 1
  fi
}

require_positive_integer "$REASONIX_INSTALL_ATTEMPTS" "REASONIX_INSTALL_ATTEMPTS"

parse_semver() {
  local raw="$1"
  if [[ "$raw" =~ [vV]?([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?) ]]; then
    local normalized="${BASH_REMATCH[1]}"
    if [[ "$normalized" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
      printf '%s\n' "$normalized"
      return 0
    fi
  fi
  return 1
}

semver_gte() {
  local a="$1" b="$2"
  local a_pre="" b_pre=""
  if [[ "$a" == *-* ]]; then
    a_pre="${a#*-}"
    a="${a%%-*}"
  fi
  if [[ "$b" == *-* ]]; then
    b_pre="${b#*-}"
    b="${b%%-*}"
  fi
  for i in 0 1 2; do
    local ai="$(echo "$a" | cut -d. -f$((i + 1)))"
    local bi="$(echo "$b" | cut -d. -f$((i + 1)))"
    ai="${ai:-0}"
    bi="${bi:-0}"
    if [[ "$ai" -gt "$bi" ]]; then return 0; fi
    if [[ "$ai" -lt "$bi" ]]; then return 1; fi
  done
  if [[ -n "$a_pre" ]] && [[ -z "$b_pre" ]]; then return 1; fi
  if [[ -z "$a_pre" ]] && [[ -n "$b_pre" ]]; then return 0; fi
  if [[ -n "$a_pre" ]] && [[ -n "$b_pre" ]]; then
    if [[ "$a_pre" == "$b_pre" ]]; then return 0; fi
    if [[ "$a_pre" < "$b_pre" ]]; then return 1; fi
    return 0
  fi
  return 0
}

version_meets_minimum() {
  if [[ -z "$REASONIX_MIN_VERSION" ]]; then return 0; fi
  local current="$1"
  local current_semver min_semver
  if ! current_semver="$(parse_semver "$current")"; then
    printf 'warning: could not parse current version %s\n' "$current" >&2
    return 1
  fi
  if ! min_semver="$(parse_semver "$REASONIX_MIN_VERSION")"; then
    printf 'warning: could not parse min version %s\n' "$REASONIX_MIN_VERSION" >&2
    return 1
  fi
  if semver_gte "$current_semver" "$min_semver"; then return 0; fi
  return 1
}

append_github_path() {
  local path_entry="$1"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "$path_entry" >>"$GITHUB_PATH"
  fi
}

activate_install_dir() {
  export PATH="$REASONIX_INSTALL_DIR:$PATH"
  append_github_path "$REASONIX_INSTALL_DIR"
  if reasonix --version >/dev/null 2>&1; then
    return 0
  fi
  rm -f "$REASONIX_INSTALL_DIR/reasonix"
  hash -r
  return 1
}

materialize_binary() {
  local candidate="$1"
  if [[ "$candidate" != "$REASONIX_INSTALL_DIR/reasonix" ]]; then
    cp "$candidate" "$REASONIX_INSTALL_DIR/reasonix"
    chmod +x "$REASONIX_INSTALL_DIR/reasonix"
  fi
}

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux)     os=linux ;;
    Darwin)    os=darwin ;;
    MINGW*|CYGWIN*|MSYS*) os=windows ;;
    *) printf 'unsupported OS: %s\n' "$(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) printf 'unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
  printf '%s %s\n' "$os" "$arch"
}

mkdir -p "$REASONIX_INSTALL_DIR"
export PATH="$REASONIX_INSTALL_DIR:$PATH"

if [[ -x "$REASONIX_INSTALL_DIR/reasonix" ]]; then
  if activate_install_dir; then
    if version_meets_minimum "$(reasonix --version)"; then
      exit 0
    fi
    printf 'installed version below minimum %s, reinstalling\n' "$REASONIX_MIN_VERSION" >&2
    rm -f "$REASONIX_INSTALL_DIR/reasonix"
    hash -r
  fi
fi

if [[ "$REASONIX_ALLOW_PREINSTALLED" == "true" ]] && command -v reasonix >/dev/null 2>&1; then
  materialize_binary "$(command -v reasonix)"
  if activate_install_dir; then
    if version_meets_minimum "$(reasonix --version)"; then
      exit 0
    fi
    printf 'preinstalled version below minimum %s, falling through to release\n' "$REASONIX_MIN_VERSION" >&2
    rm -f "$REASONIX_INSTALL_DIR/reasonix"
    hash -r
  fi
fi

read -r OS ARCH < <(detect_platform)
if [[ "$OS" == "windows" ]]; then
  EXT="zip"
else
  EXT="tar.gz"
fi

# Normalize version: strip leading 'v' if present for semver, but GitHub tag uses v.
VERSION_TAG="$REASONIX_VERSION"
if [[ ! "$VERSION_TAG" =~ ^v ]]; then
  VERSION_TAG="v$VERSION_TAG"
fi

ASSET_URL="https://github.com/${REASONIX_INSTALL_SOURCE}/releases/download/${VERSION_TAG}/reasonix-${OS}-${ARCH}.${EXT}"

download_and_extract() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  local cleanup="1"
  finish() {
    if [[ "$cleanup" == "1" ]]; then
      rm -rf "$tmpdir"
    fi
  }
  trap finish EXIT

  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 5 \
    --retry-delay 2 \
    "$ASSET_URL" \
    -o "$tmpdir/reasonix-archive.${EXT}"

  if [[ "$EXT" == "zip" ]]; then
    unzip -q "$tmpdir/reasonix-archive.${EXT}" -d "$tmpdir"
  else
    tar -xzf "$tmpdir/reasonix-archive.${EXT}" -C "$tmpdir"
  fi

  local candidate=""
  for f in "$tmpdir/reasonix" "$tmpdir/reasonix.exe"; do
    if [[ -x "$f" ]]; then
      candidate="$f"
      break
    fi
  done

  if [[ -z "$candidate" ]]; then
    printf "archive extracted but 'reasonix' binary not found\n" >&2
    return 1
  fi

  cp "$candidate" "$REASONIX_INSTALL_DIR/reasonix"
  chmod +x "$REASONIX_INSTALL_DIR/reasonix"
  cleanup="0"
  trap - EXIT
}

attempt=1
while [[ "$attempt" -le "$REASONIX_INSTALL_ATTEMPTS" ]]; do
  if download_and_extract; then
    break
  fi

  if [[ "$attempt" -eq "$REASONIX_INSTALL_ATTEMPTS" ]]; then
    printf 'Reasonix installation failed after %s attempts\n' "$REASONIX_INSTALL_ATTEMPTS" >&2
    exit 1
  fi

  sleep "$((attempt * 5))"
  attempt="$((attempt + 1))"
done

if activate_install_dir; then
  if version_meets_minimum "$(reasonix --version)"; then
    exit 0
  fi
  printf 'installed version does not satisfy minimum %s\n' "$REASONIX_MIN_VERSION" >&2
  exit 1
fi

printf "Reasonix install finished, but binary is not available\n" >&2
exit 1
