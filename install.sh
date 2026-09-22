#!/usr/bin/env bash
# InfraPack installer — macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/Mostly-Works-Studio/infrapack/main/install.sh | bash
#
# What it does:
#   1. checks for bash and Docker (and tells you how to get Docker if missing)
#   2. downloads the latest release into ~/.local/share/infrapack
#   3. links `infrapack` into ~/.local/bin and adds that to your PATH
#   4. pulls the console image and runs `infrapack doctor`
#
# Knobs:  INFRAPACK_VERSION=0.1.0   INFRAPACK_INSTALL_DIR=…   INFRAPACK_BIN_DIR=…
#         INFRAPACK_NO_MODIFY_PATH=1
set -euo pipefail

REPO="Mostly-Works-Studio/infrapack"
INSTALL_DIR="${INFRAPACK_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/infrapack}"
BIN_DIR="${INFRAPACK_BIN_DIR:-$HOME/.local/bin}"
VERSION="${INFRAPACK_VERSION:-}"

if [[ -t 1 ]]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=""; G=""; Y=""; R=""; N=""; fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%swarn%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s err%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  *) die "unsupported OS: $OS (macOS and Linux only; on Windows use WSL2)" ;;
esac
command -v curl >/dev/null || die "curl is required"
command -v tar  >/dev/null || die "tar is required"

# ------------------------------------------------------------------ docker --
if ! command -v docker >/dev/null; then
  warn "Docker is not installed. InfraPack runs everything in containers, so it needs one of:"
  if [[ "$OS" == Darwin ]]; then
    cat <<EOF
    • Docker Desktop   https://www.docker.com/products/docker-desktop/   (brew install --cask docker)
    • OrbStack         https://orbstack.dev                               (brew install orbstack)
    • Colima           brew install colima docker docker-compose && colima start
EOF
  else
    cat <<EOF
    • Docker Engine    curl -fsSL https://get.docker.com | sh   then:  sudo usermod -aG docker \$USER
EOF
  fi
  echo
  info "install Docker, start it, then re-run this installer. Continuing so the CLI is in place."
elif ! docker info >/dev/null 2>&1; then
  warn "Docker is installed but not running — start it before 'infrapack up'"
fi

# ----------------------------------------------------------------- version --
if [[ -z "$VERSION" && -n "${INFRAPACK_TARBALL:-}" ]]; then VERSION="local"; fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
             | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1 || true)"
fi
[[ -n "$VERSION" ]] || die "could not determine the latest release — set INFRAPACK_VERSION=x.y.z"

# ---------------------------------------------------------------- download --
info "installing InfraPack $VERSION to $INSTALL_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url="${INFRAPACK_TARBALL:-https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz}"
curl -fsSL "$url" -o "$tmp/infrapack.tar.gz" || die "download failed: $url"
mkdir -p "$tmp/x" && tar -xzf "$tmp/infrapack.tar.gz" -C "$tmp/x"
src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -f "$src/bin/infrapack" ]] || die "unexpected archive layout"

mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR.new"
cp -R "$src" "$INSTALL_DIR.new"
date > "$INSTALL_DIR.new/.installed-by-script"
rm -rf "$INSTALL_DIR.old"
[[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$INSTALL_DIR.old"
mv "$INSTALL_DIR.new" "$INSTALL_DIR"
rm -rf "$INSTALL_DIR.old"
chmod +x "$INSTALL_DIR/bin/infrapack"

# -------------------------------------------------------------------- link --
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/infrapack" "$BIN_DIR/infrapack"
ok "infrapack $VERSION installed"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    if [[ "${INFRAPACK_NO_MODIFY_PATH:-0}" != 1 ]]; then
      line="export PATH=\"$BIN_DIR:\$PATH\""
      for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        grep -qF "$BIN_DIR" "$rc" 2>/dev/null || printf '\n# InfraPack\n%s\n' "$line" >> "$rc"
      done
      warn "$BIN_DIR was added to your PATH in your shell profile — open a new terminal, or run:"
      printf '    %s\n' "$line"
    else
      warn "add $BIN_DIR to your PATH"
    fi ;;
esac

# ---------------------------------------------------------------- warm up --
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  info "pulling the console image"
  docker pull -q "ghcr.io/mostly-works-studio/infrapack:$VERSION" >/dev/null 2>&1 \
    || warn "could not pull the console image now; it will be fetched on first 'infrapack up'"
  "$INSTALL_DIR/bin/infrapack" doctor || true
fi

echo
printf '%sNext%s\n' "$B" "$N"
printf '  infrapack catalog          # what can be installed\n'
printf '  infrapack install postgres # add one and start it\n'
printf '  infrapack open             # the web console\n'
