#!/usr/bin/env bash
#
# One-shot setup for the VimCode Neovim config on macOS.
#
# Same dependency list as Linux; Homebrew replaces apt and the Xcode Command
# Line Tools replace build-essential. Installs a Nerd Font, points Terminal.app
# or iTerm2 at it, and pre-syncs the Neovim plugins.
#
# Safe to re-run: every step checks before it acts.
#
# Usage: ./scripts/install-macos.sh [options]
#   --skip-packages        skip Homebrew packages / uv tools
#   --skip-font            skip the Nerd Font install
#   --skip-terminal-font   install the font but leave the terminal config alone
#   --skip-plugin-sync     skip the headless Neovim plugin bootstrap
#   --step-timeout MIN     wall-clock limit per headless Neovim step (default 20)
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
STEP_TIMEOUT_MINUTES=20
DRY_RUN=0
NERD_FONT="ComicShannsMono"
NERD_FONT_VERSION="v3.5.1"
FONT_FACE="ComicShannsMono Nerd Font Mono"
# Terminal.app wants the PostScript name, not the family name.
FONT_POSTSCRIPT="ComicShannsMonoNerdFontMono-Regular"
FONT_SIZE=13

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-packages)      SKIP_PACKAGES=1 ;;
    --skip-font)          SKIP_FONT=1 ;;
    --skip-terminal-font) SKIP_TERMINAL_FONT=1 ;;
    --skip-plugin-sync)   SKIP_PLUGIN_SYNC=1 ;;
    --step-timeout)       STEP_TIMEOUT_MINUTES="$2"; shift ;;
    --dry-run)            DRY_RUN=1 ;;
    --font)               NERD_FONT="$2"; shift ;;
    --font-version)       NERD_FONT_VERSION="$2"; shift ;;
    --font-face)          FONT_FACE="$2"; shift ;;
    -h|--help)            sed -n '3,21p' "$0"; exit 0 ;;
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
# prerequisites
# --------------------------------------------------------------------------

ensure_xcode_clt() {
  step "Checking the C compiler (Xcode Command Line Tools)"
  # Treesitter parsers compile locally, so clang has to be present.
  if xcode-select -p >/dev/null 2>&1 && have cc; then
    skip "Command Line Tools already installed"
    result "xcode clt" "present"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would run: xcode-select --install"
    result "xcode clt" "would install"
    return
  fi

  note "launching the Command Line Tools installer -- accept the dialog"
  xcode-select --install 2>/dev/null || true
  note "re-run this script once the installer finishes"
  result "xcode clt" "check" "installer launched"
}

ensure_homebrew() {
  step "Checking Homebrew"
  if have brew; then
    skip "brew $(brew --version | head -n1 | awk '{print $2}') already installed"
    result "homebrew" "present"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    note "would install Homebrew from https://brew.sh"
    result "homebrew" "would install"
    return 0
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # A fresh install is not on PATH yet; the prefix differs by architecture.
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      break
    fi
  done

  if have brew; then
    ok "Homebrew installed"
    result "homebrew" "installed"
  else
    bad "Homebrew install failed"
    result "homebrew" "FAILED"
    return 1
  fi
}

# --------------------------------------------------------------------------
# packages
# --------------------------------------------------------------------------

# Same tools as the Linux script; only the package manager changes.
BREW_FORMULAE=(git neovim ripgrep fd lazygit node uv)

install_brew_formulae() {
  step "Installing packages with Homebrew"
  if ! have brew; then
    bad "brew is unavailable; skipping packages"
    result "brew packages" "FAILED" "no brew"
    return
  fi

  local formula
  for formula in "${BREW_FORMULAE[@]}"; do
    if brew list --formula --versions "$formula" >/dev/null 2>&1; then
      skip "$formula already installed"
      result "$formula" "present"
      continue
    fi
    if run brew install "$formula"; then
      ok "$formula installed"
      result "$formula" "installed"
    else
      bad "$formula install failed"
      result "$formula" "FAILED"
    fi
  done
}

install_uv_tools() {
  step "Installing ty and ruff with uv"
  if ! have uv && [ "$DRY_RUN" -eq 0 ]; then
    bad "uv is not on PATH; skipping ty and ruff"
    result "uv tools" "FAILED" "uv missing"
    return
  fi

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

  local dir tmp url
  dir="$HOME/Library/Fonts"

  if ls "$dir" 2>/dev/null | grep -qi "^${NERD_FONT}NerdFont"; then
    skip "already present in $dir"
    result "font $NERD_FONT" "present"
    return
  fi

  # The cask is the tidier route when Homebrew knows this font.
  local cask
  cask="font-$(echo "$NERD_FONT" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')-nerd-font"
  if have brew && brew info --cask "$cask" >/dev/null 2>&1; then
    if run brew install --cask "$cask"; then
      ok "installed via the $cask cask"
      result "font $NERD_FONT" "installed" "$cask"
      return
    fi
    note "cask install failed; falling back to the release zip"
  fi

  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONT_VERSION/$NERD_FONT.zip"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would download $url into $dir"
    result "font $NERD_FONT" "would install"
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
  ok "font files installed to $dir"
  result "font $NERD_FONT" "installed"
}

set_terminal_font() {
  step "Pointing the terminal at the Nerd Font"

  local touched=0

  # Terminal.app exposes its font through AppleScript, so it can be set here.
  if [ "$DRY_RUN" -eq 1 ]; then
    note "would set Terminal.app font to $FONT_POSTSCRIPT ${FONT_SIZE}pt"
    result "terminal font" "would set"
    return
  fi

  if osascript -e 'tell application "System Events" to exists application file id "com.apple.Terminal"' >/dev/null 2>&1; then
    local default_set
    default_set="$(osascript -e 'tell application "Terminal" to get name of default settings' 2>/dev/null)"
    if [ -n "$default_set" ]; then
      if osascript \
          -e "tell application \"Terminal\" to set font name of settings set \"$default_set\" to \"$FONT_POSTSCRIPT\"" \
          -e "tell application \"Terminal\" to set font size of settings set \"$default_set\" to $FONT_SIZE" \
          >/dev/null 2>&1; then
        ok "Terminal.app profile '$default_set' set to $FONT_POSTSCRIPT"
        result "terminal font" "set" "Terminal.app"
        touched=1
      else
        note "Terminal.app refused the font name -- check it in Settings > Profiles > Text"
      fi
    fi
  fi

  if [ -d "/Applications/iTerm.app" ]; then
    note "iTerm2 detected: set the font in Settings > Profiles > Text > Font"
    note "  choose '$FONT_FACE'"
  fi

  if [ "$touched" -eq 0 ]; then
    note "set your terminal font to '$FONT_FACE' by hand"
    note "  kitty: 'font_family $FONT_FACE'   alacritty: font.normal.family"
    note "  wezterm: wezterm.font('$FONT_FACE')   ghostty: 'font-family = $FONT_FACE'"
    result "terminal font" "skipped" "manual"
  fi
}

# --------------------------------------------------------------------------
# Neovim plugin bootstrap
# --------------------------------------------------------------------------

# Runs a command with a wall-clock limit. MacOS has no `timeout` unless
# coreutils is installed, so fall back to a background watchdog. Returns 124 on
# timeout, matching what `timeout` itself reports.
run_with_timeout() {
  local seconds="$1"; shift
  local status

  if have timeout; then
    timeout "$seconds" "$@"
    return $?
  elif have gtimeout; then
    gtimeout "$seconds" "$@"
    return $?
  fi

  "$@" &
  local pid=$!
  ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null
  status=$?
  kill "$watcher" 2>/dev/null
  # 143 = 128 + SIGTERM, i.e. the watchdog fired.
  [ "$status" -eq 143 ] && return 124
  return $status
}

nvim_headless() {
  local label="$1"; shift
  local seconds=$((STEP_TIMEOUT_MINUTES * 60))
  local status

  printf '    nvim %s (up to %s min) ...\n' "$label" "$STEP_TIMEOUT_MINUTES"
  # The file argument makes argc() non-zero, which stops autocmds.lua from
  # opening the session layout (explorer + terminals) part-way through a
  # long headless run.
  run_with_timeout "$seconds" nvim --headless "$CONFIG_DIR/init.lua" "$@" +qa 2>&1 | sed 's/^/      /'
  status=${PIPESTATUS[0]}

  if [ "$status" -eq 124 ]; then
    note "$label: still running after $STEP_TIMEOUT_MINUTES min, stopped it"
    note "  run this inside nvim to finish: $*"
    result "$label" "timed out"
  elif [ "$status" -eq 0 ]; then
    ok "$label: done"
    result "$label" "done"
  else
    note "$label: nvim exited $status (usually harmless, check inside nvim)"
    result "$label" "check"
  fi
}

# Mason shells out to python to build debugpy.
have_usable_python() {
  local candidate
  for candidate in python3 python; do
    if have "$candidate" && "$candidate" --version >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# LazyVim's build step for markdown-preview calls mkdp#util#install(), which
# opens an interactive terminal buffer to run install.sh. Under --headless
# there is no UI to drive it, so it sits there forever. Check for the prebuilt
# binary instead and point at the manual fix when it is missing.
check_markdown_preview() {
  local app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/markdown-preview.nvim/app"

  if [ ! -d "$app_dir" ]; then
    skip "markdown-preview: plugin not installed, nothing to check"
    result "markdown-preview" "skipped"
    return
  fi

  if ls "$app_dir/bin/markdown-preview-"* >/dev/null 2>&1; then
    ok "markdown-preview: prebuilt binary present"
    result "markdown-preview" "present"
  else
    note "markdown-preview: prebuilt binary missing"
    note "  finish it by hand: cd '$app_dir' && ./install.sh"
    result "markdown-preview" "check" "run install.sh"
  fi
}

bootstrap_plugins() {
  step "Bootstrapping Neovim plugins (this takes a few minutes)"
  if ! have nvim; then
    note "nvim is not on PATH yet -- reopen your shell, then run: nvim"
    result "plugin sync" "skipped" "no nvim"
    return
  fi
  # install + restore, not sync: this pins plugins to lazy-lock.json rather
  # than updating them. Note that install still prunes entries for plugins the
  # config no longer references.
  nvim_headless "plugin install" "+Lazy! install" "+Lazy! restore"

  if have_usable_python; then
    nvim_headless "debugpy install" "+MasonInstall debugpy"
  else
    note "debugpy: skipped, no usable Python on PATH"
    result "debugpy install" "skipped" "no python"
  fi

  check_markdown_preview
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
  echo "this script is for macOS; use install-linux.sh instead" >&2
  exit 1
fi

printf '\n%s  VimCode setup -- macOS (%s)%s\n' "$C_HEAD" "$(uname -m)" "$C_OFF"
[ "$DRY_RUN" -eq 1 ] && printf '%s  (dry run: nothing will be changed)%s\n' "$C_NOTE" "$C_OFF"

if [ "$SKIP_PACKAGES" -eq 0 ]; then
  ensure_xcode_clt
  ensure_homebrew
  install_brew_formulae
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
printf '    1. Open a new shell so PATH picks up brew and ~/.local/bin.\n'
printf '    2. Restart your terminal so the font change takes effect.\n'
printf "    3. Run 'nvim' and then ':checkhealth' to confirm everything is wired up.\n\n"

exit $FAILED
