# 👨🏻‍💻 VimCode

A NeoVim setup intended to replace VS Code.

__Warning:__ After replacing VS Code with VimCode, you may experience lightning fast IDE performance and a lot of less RAM usage. Please enjoy responsibly.

___credit___: Modified from starter template of [LazyVim](https://github.com/LazyVim/LazyVim).

## Quick start

The scripts in `scripts/` do the whole setup: install every dependency, install
the Nerd Font, point the terminal at it, and pre-install the plugins. They are
safe to re-run -- every step checks before it acts.

### Windows (winget)

```powershell
git clone https://github.com/hhuang91/VimCode.git $env:LOCALAPPDATA\nvim
powershell -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\nvim\scripts\install-windows.ps1
```

### Linux (apt / dnf / pacman)

```bash
git clone https://github.com/hhuang91/VimCode.git ~/.config/nvim
bash ~/.config/nvim/scripts/install-linux.sh
```

### MacOS (Homebrew)

```bash
git clone https://github.com/hhuang91/VimCode.git ~/.config/nvim
bash ~/.config/nvim/scripts/install-macos.sh
```

Then open a new terminal and run `nvim`.

### What the scripts do

1. Install the packages listed under [Additional Package](#additional-package)
   (winget on Windows, apt/dnf/pacman/zypper on Linux, Homebrew on MacOS)
2. Install `ty` and `ruff` with `uv`
3. Download the [ComicShannsMono](https://github.com/ryanoasis/nerd-fonts) Nerd
   Font and install it for the current user (no admin needed)
4. Set the terminal font face -- Windows Terminal on Windows, GNOME Terminal on
   Linux, Terminal.app on MacOS. Any other terminal prints instructions instead.
5. Run a headless `Lazy! install` + `Lazy! restore`, install `debugpy` through
   Mason, and check the `markdown-preview` binary -- the two items under
   [Troubleshoot](#troubleshoot)

Plugins are pinned to `lazy-lock.json` rather than updated, so a fresh machine
gets exactly the versions in this repo.

Every headless Neovim step runs under a wall-clock limit (20 minutes by
default). Without one a plugin build that waits on something interactive hangs
the whole setup with nothing on screen to explain why -- which is exactly what
`markdown-preview` does: its build opens a terminal buffer to run `install.cmd`,
and under `--headless` there is no UI to drive it. The scripts therefore check
for its prebuilt binary rather than trying to build it, and tell you the one
command to run if it is missing.

### Useful flags

Run with `--dry-run` (`-DryRun` on Windows) first to see what would happen
without changing anything.

| Windows | Linux / MacOS | Effect |
| --- | --- | --- |
| `-DryRun` | `--dry-run` | print the plan, change nothing |
| `-SkipPackages` | `--skip-packages` | leave package installs alone |
| `-SkipFont` | `--skip-font` | do not install the font |
| `-SkipTerminalFont` | `--skip-terminal-font` | install the font but do not touch the terminal config |
| `-SkipPluginSync` | `--skip-plugin-sync` | do not pre-install plugins |
| `-NerdFont JetBrainsMono` | `--font JetBrainsMono` | use a different Nerd Font release |
| `-FontFace '<family>'` | `--font-face '<family>'` | family name written into the terminal config |
| `-StepTimeoutMinutes 20` | `--step-timeout 20` | wall-clock limit per headless Neovim step |

Three notes on what the scripts touch:

- On Windows, the Windows Terminal `settings.json` is rewritten by
  `ConvertTo-Json`, which drops comments and reformatting. A timestamped
  `.vimcode-backup-*` copy is written next to it first.
- On Linux, `~/.local/bin` is appended to `~/.bashrc` / `~/.zshrc` if it is not
  already on `PATH`. Pass `--no-path-edit` to skip that.
- `Lazy! install` rewrites `lazy-lock.json` when it prunes entries for plugins
  the config no longer references. That is a tracked file, so check `git diff`
  after a bootstrap run.

Fonts already installed are left alone. Windows loads registered per-user fonts
at logon and keeps the files open, so an installed `.otf` cannot be overwritten
-- and does not need to be. The script compares hashes and skips what already
matches, which is why re-running it is safe. (Logging out does not release
those handles; the fonts are simply loaded again at the next logon.)

----

The rest of this README is the manual version of the same steps, for reference
or when a script step fails.

## Nerdfont

Download load [Nerdfont](https://www.nerdfonts.com/) and install

Recommended: [ComicShannsMono](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/ComicShannsMono.zip) (_Who doesn't like comic sans?_)

Then make sure to enable the font in terminals

**for windows** right click title bar on powershell --> settings --> on sidebar, scroll down to `Profiles` section and click `Windows Powershell` --> on the right, scroll down to `additional settings` section and click appearance --> in `Text` section, select Nerdfont in `Font face`

**for MacOS** Enter settings for terminal --> Profile --> Font

The family to pick is `ComicShannsMono Nerd Font Mono`. The zip also contains
`ComicShannsMono Nerd Font` (double-width icons) and
`ComicShannsMono Nerd Font Propo` (proportional), which are not what you want in
a terminal.

## Additional Package

Note that these additional packages should be installed FIRST, before starting nvim to make sure eveything compiles on first try.

NeoVim itself must be `0.11.2` or newer (LazyVim's floor). This matters on
Linux, where the distro package is usually older -- `install-linux.sh` installs
the official release tarball into `~/.local` instead.

Python debugging needs a real `python` on `PATH`, because Mason shells out to it
to build `debugpy`. On Windows the 0-byte Microsoft Store alias in `WindowsApps`
does not count -- Mason reports `Unable to find python3 installation in PATH`
even though `where python` finds something. `uv python install --default` gives
you a real one.

### Windows

#### Powershell 7.X

Newer version of the powershell. Should be more reliable than default legacy version
Note that the `wix` flag is very important -- otherwise, winget will install powershell to AppData folder, which can cause permission issues

`winget install --id Microsoft.PowerShell --source winget --installer-type wix`

#### NeoVim

`winget install -e --id Neovim.Neovim`

#### Git

Needed by `lazy.nvim` to fetch plugins

`winget install -e --id Git.Git`

#### fd-find

`winget install -e --id sharkdp.fd`

#### node.js

~~For support Lsp Mason installing Pyright~~
NOT for lsp anymore (switched to ty), but for copilot and markdownpreview

`winget install OpenJS.NodeJS`

#### uv

Provides `ty` and `ruff` below

`winget install -e --id astral-sh.uv`

#### ty

For fast LSP

`uv tool install ty@latest`

#### Ruff

`uv tool install ruff@latest`

or

Start `nvim` from an activated python environment

#### RipGrep

`winget install BurntSushi.ripgrep.GNU`

#### C compiler to power treesitter

`winget install --id=BrechtSanders.WinLibs.POSIX.UCRT -e`

#### LazyGit

`winget install -e --id=JesseDuffield.lazygit`

----

### Linux

#### C compiler

~~Zig (lightweight)~~ (Does not work out of the box)

~~`sudo apt install zig`~~

Build essentials

`sudo apt install build-essential`

#### NeoVim (from tarball)

The apt package is older than 0.11.2, so install the official build:

```bash
mkdir -p ~/.local/share/nvim-release ~/.local/bin
curl -fsSL https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz \
  | tar -xz -C ~/.local/share/nvim-release --strip-components=1
ln -sf ~/.local/share/nvim-release/bin/nvim ~/.local/bin/nvim
```

#### uv (installer script)

`curl -LsSf https://astral.sh/uv/install.sh | sh`

#### ty

(Same as windows)

`uv tool install ty@latest`

#### LazyGit

`sudo apt install lazygit`

Only packaged on recent Debian/Ubuntu. Otherwise grab the binary from the
[releases page](https://github.com/jesseduffield/lazygit/releases) and drop it
in `~/.local/bin`.

#### Node.js

`curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash`

`source ~/.bashrc`

`nvm install --lts`

#### RipGrep

`sudo apt install ripgrep`

#### fd-find

`sudo apt install fd-find`

Debian and Ubuntu install the binary as `fdfind`; snacks.nvim looks for `fd`, so
link it:

`ln -sf "$(command -v fdfind)" ~/.local/bin/fd`

----

### MacOS

Same tool list as Linux. Homebrew replaces apt, and the Xcode Command Line Tools
replace `build-essential`.

#### C compiler (Xcode CLT)

`xcode-select --install`

#### Everything else

`brew install git neovim ripgrep fd lazygit node uv`

Homebrew's `neovim` formula is current, so no tarball dance is needed here, and
`node` from brew is fine in place of nvm.

#### ty and Ruff

(Same as windows)

`uv tool install ty@latest`

`uv tool install ruff@latest`

#### Nerdfont (cask)

`brew install --cask font-comic-shanns-mono-nerd-font`

----

#### Troubleshoot

**Markdown Preview**:
Sometimes, `markdownpreview` does not work properly -- `<leader>cp` results in nothing happening. This is likely due to failed installation of markdown preview. A quick fix is to go to `C:\Users\Heyuan\AppData\Local\nvim-data\lazy\markdown-preview.nvim\app`, open a terminal, and run `install.cmd`

**Python debugging**:
If you see message like 'Executable `debugpy-adapter` not found, fix the adapter definition for `python` (ENOENT: no such file or directory)'. It usually means that debugpy is not installed in Mason. Run this command in LazyVim: `:MasonInstall debugpy`
