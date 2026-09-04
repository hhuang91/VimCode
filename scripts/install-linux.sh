#!/usr/bin/env bash
#
# One-shot setup for the VimCode Neovim config on Linux.
#
# Installs every external dependency this config needs, installs a Nerd Font,
# points GNOME Terminal at it when that is the terminal in use, and pre-syncs
# the Neovim plugins so nothing has to compile on first launch.
#
# Safe to re-run: every step checks before it acts.
#
# Usage: ./scripts/install-linux.sh [options]
#   --skip-packages        skip distro packages / node / uv tools
#   --skip-font            skip the Nerd Font download and install
#   --skip-terminal-font   install the font but leave the terminal config alone
#   --skip-plugin-sync     skip the headless Neovim plugin bootstrap
#   --no-path-edit         do not append ~/.local/bin to your shell rc
#   --font NAME            Nerd Font release to install (default ComicShannsMono)
#   --font-version VER     Nerd Font release tag (default v3.5.1)
#   --font-face NAME       family name written into the terminal config
#   --dry-run              print what would happen, change nothing

set -uo pipefail

# --------------------------------------------------------------------------
# options
# --------------------------------------------------------------------------

SKIP_PACKAGES=0
SKIP_FONT=0
SKIP_TERMINAL_FONT=0
SKIP_PLUGIN_SYNC=0
NO_PATH_EDIT=0
DRY_RUN=0
NERD_FONT="ComicShannsMono"
NERD_FONT_VERSION="v3.5.1"
FONT_FACE="ComicShannsMono Nerd Font Mono"

# LazyVim's floor. Every distro package is older than this today, so we install
# the official stable tarball into ~/.local instead of using the package manager.
MIN_NVIM="0.11.2"

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-packages)      SKIP_PACKAGES=1 ;;
    --skip-font)          SKIP_FONT=1 ;;
    --skip-terminal-font) SKIP_TERMINAL_FONT=1 ;;
    --skip-plugin-sync)   SKIP_PLUGIN_SYNC=1 ;;
    --no-path-edit)       NO_PATH_EDIT=1 ;;
    --dry-run)            DRY_RUN=1 ;;
    --font)               NERD_FONT="$2"; shift ;;
    --font-version)       NERD_FONT_VERSION="$2"; shift ;;
    --font-face)          FONT_FACE="$2"; shift ;;
    -h|--help)            sed -n '3,23p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# --------------------------------------------------------------------------
# output helpers
# --------------------------------------------------------------------------

if [ -t 1 ]; then
  C_STEP=$'\033[36m'; C_OK=$'\033[32m'; C_SKIP=$'\033[90m'
  C_NOTE=$'\033[33m'; C_BAD=$'\033[31m'; C_HEAD=$'\033[35m'; C_OFF=$'\033[0m'
else
  C_STEP=""; C_OK=""; C_SKIP=""; C_NOTE=""; C_BAD=""; C_HEAD=""; C_OFF=""
fi

RESULTS=()
FAILED=0

step()   { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok()     { printf '%s    %s%s\n' "$C_OK"   "$1" "$C_OFF"; }
skip()   { printf '%s    %s%s\n' "$C_SKIP" "$1" "$C_OFF"; }
note()   { printf '%s    %s%s\n' "$C_NOTE" "$1" "$C_OFF"; }
bad()    { printf '%s    %s%s\n' "$C_BAD"  "$1" "$C_OFF"; }
result() { RESULTS+=("$1|$2|${3:-}"); [ "$2" = "FAILED" ] && FAILED=1; return 0; }

have() { command -v "$1" >/dev/null 2>&1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would run: $*"
    return 0
  fi
  "$@"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

# --------------------------------------------------------------------------
# platform detection
# --------------------------------------------------------------------------

case "$(uname -m)" in
  x86_64|amd64)  NVIM_ARCH="x86_64"; LG_ARCH="x86_64" ;;
  aarch64|arm64) NVIM_ARCH="arm64";  LG_ARCH="arm64" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if   have apt-get; then PM="apt"
elif have dnf;     then PM="dnf"
elif have pacman;  then PM="pacman"
elif have zypper;  then PM="zypper"
else PM="none"
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if have sudo; then SUDO="sudo"; fi
fi

pm_install() {
  # Package names differ per distro; callers pass the already-mapped names.
  [ $# -eq 0 ] && return 0
  case "$PM" in
    apt)    run $SUDO apt-get install -y "$@" ;;
    dnf)    run $SUDO dnf install -y "$@" ;;
    pacman) run $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) run $SUDO zypper install -y "$@" ;;
    *)      bad "no supported package manager found; install manually: $*"; return 1 ;;
  esac
}

pm_refresh() {
  case "$PM" in
    apt)    run $SUDO apt-get update ;;
    pacman) run $SUDO pacman -Sy --noconfirm ;;
    *)      return 0 ;;
  esac
}

# Map a logical name to this distro's package name. Empty means "not packaged".
pkg_name() {
  case "$1:$PM" in
    cc:apt)          echo "build-essential" ;;
    cc:dnf)          echo "gcc make" ;;
    cc:pacman)       echo "base-devel" ;;
    cc:zypper)       echo "gcc make" ;;
    fd:apt)          echo "fd-find" ;;
    fd:dnf)          echo "fd-find" ;;
    fd:pacman)       echo "fd" ;;
    fd:zypper)       echo "fd" ;;
    ripgrep:*)       echo "ripgrep" ;;
    git:*)           echo "git" ;;
    curl:*)          echo "curl" ;;
    unzip:*)         echo "unzip" ;;
    fontconfig:*)    echo "fontconfig" ;;
    *)               echo "" ;;
  esac
}

version_ge() {
  # version_ge A B  ->  true when A >= B
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

github_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1
}

LOCAL_BIN="$HOME/.local/bin"

ensure_local_bin_on_path() {
  mkdir -p "$LOCAL_BIN"
  case ":$PATH:" in *":$LOCAL_BIN:"*) ;; *) PATH="$LOCAL_BIN:$PATH" ;; esac
  export PATH

  [ "$NO_PATH_EDIT" -eq 1 ] && return 0
  [ "$DRY_RUN" -eq 1 ] && return 0

  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -q 'VimCode: keep ~/.local/bin on PATH' "$rc" && continue
    {
      echo ''
      echo '# VimCode: keep ~/.local/bin on PATH'
      echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac'
      echo 'export PATH'
    } >> "$rc"
    ok "added ~/.local/bin to PATH in $rc"
  done
}

# --------------------------------------------------------------------------
# packages
# --------------------------------------------------------------------------

install_base_packages() {
  local wanted=() logical name
  for logical in cc ripgrep fd git curl unzip fontconfig; do
    name="$(pkg_name "$logical")"
    [ -n "$name" ] && wanted+=($name)
  done

  step "Installing base packages with $PM"
  if [ "$PM" = "none" ]; then
    bad "no supported package manager; install these yourself: ${wanted[*]}"
    result "base packages" "FAILED" "no package manager"
    return
  fi

  pm_refresh
  if pm_install "${wanted[@]}"; then
    ok "base packages installed"
    result "base packages" "installed" "${wanted[*]}"
  else
    bad "package install failed"
    result "base packages" "FAILED"
  fi

  # Debian/Ubuntu ship the fd binary as 'fdfind' to avoid a name clash.
  if ! have fd && have fdfind; then
    ensure_local_bin_on_path
    run ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
    ok "linked fdfind -> $LOCAL_BIN/fd"
    result "fd shim" "installed"
  fi
}

install_neovim() {
  step "Installing Neovim (>= $MIN_NVIM)"

  if have nvim; then
    local current
    current="$(nvim --version | head -n1 | sed -n 's/^NVIM v\([0-9.]*\).*/\1/p')"
    if [ -n "$current" ] && version_ge "$current" "$MIN_NVIM"; then
      skip "Neovim $current already installed"
      result "neovim" "present" "$current"
      return
    fi
    note "Neovim $current is older than $MIN_NVIM; installing the official build"
  fi

  local tag url dest
  tag="$(github_latest_tag neovim/neovim)"
  [ -z "$tag" ] && tag="stable"
  url="https://github.com/neovim/neovim/releases/download/$tag/nvim-linux-$NVIM_ARCH.tar.gz"
  dest="$HOME/.local/share/nvim-release"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install $url into $dest"
    result "neovim" "would install" "$tag"
    return
  fi

  ensure_local_bin_on_path
  rm -rf "$dest"
  mkdir -p "$dest"
  if ! curl -fsSL "$url" | tar -xz -C "$dest" --strip-components=1; then
    bad "could not download or unpack $url"
    result "neovim" "FAILED"
    return
  fi
  ln -sf "$dest/bin/nvim" "$LOCAL_BIN/nvim"
  hash -r 2>/dev/null || true
  ok "Neovim $tag installed to $dest"
  result "neovim" "installed" "$tag"
}

install_lazygit() {
  step "Installing lazygit"
  if have lazygit; then
    skip "lazygit already installed"
    result "lazygit" "present"
    return
  fi

  # Packaged on Arch and Fedora, and on recent Debian/Ubuntu only. Fall back to
  # the upstream release binary when the distro does not carry it.
  if pm_install lazygit 2>/dev/null && have lazygit; then
    ok "lazygit installed from $PM"
    result "lazygit" "installed" "$PM"
    return
  fi

  local tag version url tmp
  tag="$(github_latest_tag jesseduffield/lazygit)"
  version="${tag#v}"
  if [ -z "$version" ]; then
    bad "could not resolve the latest lazygit release"
    result "lazygit" "FAILED"
    return
  fi
  url="https://github.com/jesseduffield/lazygit/releases/download/$tag/lazygit_${version}_Linux_${LG_ARCH}.tar.gz"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install $url into $LOCAL_BIN"
    result "lazygit" "would install" "$tag"
    return
  fi

  ensure_local_bin_on_path
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" | tar -xz -C "$tmp" lazygit; then
    install -m 0755 "$tmp/lazygit" "$LOCAL_BIN/lazygit"
    ok "lazygit $tag installed to $LOCAL_BIN"
    result "lazygit" "installed" "$tag"
  else
    bad "could not download $url"
    result "lazygit" "FAILED"
  fi
  rm -rf "$tmp"
}

install_node() {
  step "Installing Node.js (for Copilot and markdown-preview)"
  if have node; then
    skip "node $(node --version) already installed"
    result "node" "present" "$(node --version)"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install nvm and run: nvm install --lts"
    result "node" "would install"
    return
  fi

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi

  # shellcheck disable=SC1091
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm install --lts
    ok "node $(node --version) installed via nvm"
    result "node" "installed" "$(node --version)"
  else
    bad "nvm install failed"
    result "node" "FAILED"
  fi
}

install_uv_tools() {
  step "Installing uv, ty and ruff"

  if ! have uv; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "would install uv from https://astral.sh/uv/install.sh"
    else
      curl -fsSL https://astral.sh/uv/install.sh | sh
      ensure_local_bin_on_path
      hash -r 2>/dev/null || true
    fi
  else
    skip "uv already installed"
  fi

  if ! have uv && [ "$DRY_RUN" -eq 0 ]; then
    bad "uv is still not on PATH; skipping ty and ruff"
    result "uv" "FAILED"
    return
  fi
  result "uv" "present"

  local tool
  for tool in ty ruff; do
    if run uv tool install "$tool@latest"; then
      ok "$tool ready"
      result "$tool" "installed"
    else
      bad "$tool install failed"
      result "$tool" "FAILED"
    fi
  done
}

# --------------------------------------------------------------------------
# font
# --------------------------------------------------------------------------

install_nerd_font() {
  step "Installing the $NERD_FONT Nerd Font"

  local url dir tmp
  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONT_VERSION/$NERD_FONT.zip"
  dir="$HOME/.local/share/fonts/$NERD_FONT"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would download $url into $dir"
    result "font $NERD_FONT" "would install"
    return
  fi

  if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    skip "already present in $dir"
    result "font $NERD_FONT" "present"
    return
  fi

  tmp="$(mktemp -d)"
  if ! curl -fsSL -o "$tmp/font.zip" "$url"; then
    bad "could not download $url"
    result "font $NERD_FONT" "FAILED"
    rm -rf "$tmp"
    return
  fi

  mkdir -p "$dir"
  unzip -q -o "$tmp/font.zip" -d "$tmp/extracted"
  find "$tmp/extracted" \( -name '*.ttf' -o -name '*.otf' \) -exec cp {} "$dir/" \;
  rm -rf "$tmp"

  fc-cache -f "$dir" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1
  ok "$(find "$dir" -type f | wc -l) font file(s) installed to $dir"
  result "font $NERD_FONT" "installed"
}

set_terminal_font() {
  step "Pointing the terminal at the Nerd Font"

  # GNOME Terminal is the only Linux terminal with a config we can set
  # reliably from a script. Everything else is a config file the user owns.
  if ! have gsettings || ! gsettings list-schemas 2>/dev/null | grep -q '^org.gnome.Terminal.ProfilesList$'; then
    note "GNOME Terminal not detected -- set the font face by hand:"
    note "  $FONT_FACE"
    note "  kitty: 'font_family $FONT_FACE'   alacritty: font.normal.family"
    note "  wezterm: wezterm.font('$FONT_FACE')   ghostty: 'font-family = $FONT_FACE'"
    result "terminal font" "skipped" "manual"
    return
  fi

  local profile path
  profile="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | sed "s/^'//; s/'\$//")"
  if [ -z "$profile" ]; then
    note "could not read the default GNOME Terminal profile"
    result "terminal font" "skipped" "no profile"
    return
  fi
  path="/org/gnome/terminal/legacy/profiles:/:$profile/"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would set GNOME Terminal profile $profile font to '$FONT_FACE 12'"
    result "terminal font" "would set"
    return
  fi

  gsettings set "org.gnome.Terminal.Legacy.Profile:$path" use-system-font false
  gsettings set "org.gnome.Terminal.Legacy.Profile:$path" font "$FONT_FACE 12"
  ok "GNOME Terminal font set to '$FONT_FACE 12'"
  result "terminal font" "set" "$FONT_FACE"
}

# --------------------------------------------------------------------------
# Neovim plugin bootstrap
# --------------------------------------------------------------------------

nvim_headless() {
  local label="$1"; shift
  printf '    nvim %s ...\n' "$label"
  # The file argument makes argc() non-zero, which stops autocmds.lua from
  # opening the session layout (explorer + terminals) part-way through a
  # long headless run.
  if nvim --headless "$CONFIG_DIR/init.lua" "$@" +qa 2>&1 | sed 's/^/      /'; then
    ok "$label: done"
    result "$label" "done"
  else
    note "$label: nvim exited non-zero (usually harmless, check inside nvim)"
    result "$label" "check"
  fi
}

bootstrap_plugins() {
  step "Bootstrapping Neovim plugins (this takes a few minutes)"
  if ! have nvim; then
    note "nvim is not on PATH yet -- reopen your shell, then run: nvim"
    result "plugin sync" "skipped" "no nvim"
    return
  fi
  # install + restore, not sync: this pins plugins to lazy-lock.json instead
  # of updating them and rewriting the committed lockfile.
  nvim_headless "plugin install" "+Lazy! install" "+Lazy! restore"
  # Pre-empts the two items in the README's troubleshooting section.
  nvim_headless "debugpy install" "+MasonInstall debugpy"
  nvim_headless "markdown-preview build" "+Lazy! build markdown-preview.nvim"
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

printf '\n%s  VimCode setup -- Linux (%s, %s)%s\n' "$C_HEAD" "$PM" "$(uname -m)" "$C_OFF"
[ "$DRY_RUN" -eq 1 ] && printf '%s  (dry run: nothing will be changed)%s\n' "$C_NOTE" "$C_OFF"

if [ "$(id -u)" -ne 0 ] && [ -z "$SUDO" ] && [ "$SKIP_PACKAGES" -eq 0 ]; then
  bad "sudo not found and not running as root -- distro packages will fail"
fi

ensure_local_bin_on_path

if [ "$SKIP_PACKAGES" -eq 0 ]; then
  install_base_packages
  install_neovim
  install_lazygit
  install_node
  install_uv_tools
else
  step "Skipping packages (--skip-packages)"
fi

if [ "$SKIP_FONT" -eq 0 ]; then
  install_nerd_font
else
  step "Skipping font install (--skip-font)"
fi

if [ "$SKIP_TERMINAL_FONT" -eq 0 ]; then
  set_terminal_font
else
  step "Skipping terminal config (--skip-terminal-font)"
fi

if [ "$SKIP_PLUGIN_SYNC" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  bootstrap_plugins
else
  step "Skipping plugin bootstrap"
fi

printf '\n%s  Summary%s\n' "$C_HEAD" "$C_OFF"
if [ "${#RESULTS[@]}" -gt 0 ]; then
  for line in "${RESULTS[@]}"; do
    printf '    %-26s %-14s %s\n' "${line%%|*}" "$(echo "$line" | cut -d'|' -f2)" "${line##*|}"
  done
fi

printf '\n%s  Next steps:%s\n' "$C_HEAD" "$C_OFF"
printf '    1. Open a new shell so PATH and the font cache take effect.\n'
printf '    2. If your terminal is not GNOME Terminal, set its font to "%s".\n' "$FONT_FACE"
printf "    3. Run 'nvim' and then ':checkhealth' to confirm everything is wired up.\n\n"

exit $FAILED
