#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot setup for the VimCode Neovim config on Windows.

.DESCRIPTION
    Installs every external dependency this config needs (winget packages +
    uv tools), installs a Nerd Font per-user, points Windows Terminal at it,
    and pre-syncs the Neovim plugins so nothing has to compile on first launch.

    Safe to re-run: every step checks before it acts.

.PARAMETER SkipPackages
    Do not install winget packages / uv tools.

.PARAMETER SkipFont
    Do not download or install the Nerd Font.

.PARAMETER SkipTerminalFont
    Install the font but leave Windows Terminal's settings.json alone.

.PARAMETER SkipPluginSync
    Do not run the headless Neovim plugin bootstrap at the end.

.PARAMETER FontFace
    Font family written into Windows Terminal. Defaults to the monospaced
    Nerd Font variant, which is the one terminals render best.

.PARAMETER DryRun
    Print what would happen without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1

.EXAMPLE
    .\scripts\install-windows.ps1 -NerdFont JetBrainsMono -FontFace 'JetBrainsMono Nerd Font Mono'
#>
[CmdletBinding()]
param(
    [switch] $SkipPackages,
    [switch] $SkipFont,
    [switch] $SkipTerminalFont,
    [switch] $SkipPluginSync,
    [string] $NerdFont        = 'ComicShannsMono',
    [string] $NerdFontVersion = 'v3.5.1',
    [string] $FontFace        = 'ComicShannsMono Nerd Font Mono',
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# output helpers
# --------------------------------------------------------------------------

$script:Results = New-Object System.Collections.ArrayList

function Write-Step { param([string] $Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Skip { param([string] $Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Note { param([string] $Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Bad  { param([string] $Message) Write-Host "    $Message" -ForegroundColor Red }

function Add-Result {
    param([string] $Item, [string] $Status, [string] $Detail = '')
    [void] $script:Results.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
}

# winget and MSI installers edit the persisted PATH, not this process's copy.
# Re-read it so later steps in this same run can find what we just installed.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Test-Command {
    param([string] $Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# --------------------------------------------------------------------------
# winget packages
# --------------------------------------------------------------------------

# Cmds are what we probe for on PATH (any one is enough); Id is the winget
# package. The 'wix' installer type on PowerShell 7 is deliberate -- without it
# winget drops pwsh into AppData, which causes permission trouble later.
$Packages = @(
    @{ Name = 'PowerShell 7';         Id = 'Microsoft.PowerShell';             Cmds = @('pwsh');                 Args = @('--installer-type', 'wix') }
    @{ Name = 'Git';                  Id = 'Git.Git';                          Cmds = @('git');                  Args = @() }
    @{ Name = 'Neovim';               Id = 'Neovim.Neovim';                    Cmds = @('nvim');                 Args = @() }
    @{ Name = 'fd';                   Id = 'sharkdp.fd';                       Cmds = @('fd');                   Args = @() }
    @{ Name = 'ripgrep';              Id = 'BurntSushi.ripgrep.GNU';           Cmds = @('rg');                   Args = @() }
    @{ Name = 'Node.js';              Id = 'OpenJS.NodeJS';                    Cmds = @('node');                 Args = @() }
    @{ Name = 'C compiler (WinLibs)'; Id = 'BrechtSanders.WinLibs.POSIX.UCRT'; Cmds = @('gcc', 'clang', 'cc');   Args = @() }
    @{ Name = 'lazygit';              Id = 'JesseDuffield.lazygit';            Cmds = @('lazygit');              Args = @() }
    @{ Name = 'uv';                   Id = 'astral-sh.uv';                     Cmds = @('uv');                   Args = @() }
)

function Test-WingetPackage {
    param([string] $Id)
    $null = & winget list --id $Id --exact --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackage {
    param([hashtable] $Package)

    foreach ($cmd in $Package.Cmds) {
        if (Test-Command $cmd) {
            Write-Skip "$($Package.Name): already on PATH ($cmd)"
            Add-Result $Package.Name 'present'
            return
        }
    }

    if (Test-WingetPackage $Package.Id) {
        Write-Skip "$($Package.Name): installed (not yet on PATH -- reopen your shell)"
        Add-Result $Package.Name 'present' 'restart shell'
        return
    }

    if ($DryRun) {
        Write-Note "$($Package.Name): would run winget install $($Package.Id)"
        Add-Result $Package.Name 'would install'
        return
    }

    Write-Host "    installing $($Package.Name) ($($Package.Id)) ..."
    $wingetArgs = @(
        'install', '--id', $Package.Id, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    ) + $Package.Args

    & winget @wingetArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$($Package.Name): installed"
        Add-Result $Package.Name 'installed'
    } else {
        Write-Bad "$($Package.Name): winget exited $LASTEXITCODE"
        Add-Result $Package.Name 'FAILED' "winget exit $LASTEXITCODE"
    }
    Update-SessionPath
}

function Install-UvTool {
    param([string] $Tool)

    if (-not (Test-Command 'uv')) {
        Write-Bad "${Tool}: uv not available, skipping"
        Add-Result $Tool 'FAILED' 'uv missing'
        return
    }
    if ($DryRun) {
        Write-Note "${Tool}: would run uv tool install $Tool@latest"
        Add-Result $Tool 'would install'
        return
    }

    Write-Host "    uv tool install $Tool@latest ..."
    & uv tool install "$Tool@latest"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "${Tool}: ready"
        Add-Result $Tool 'installed'
    } else {
        Write-Bad "${Tool}: uv exited $LASTEXITCODE"
        Add-Result $Tool 'FAILED' "uv exit $LASTEXITCODE"
    }
}

# --------------------------------------------------------------------------
# Nerd Font
# --------------------------------------------------------------------------

function Install-NerdFont {
    param([string] $Name, [string] $Version)

    $url     = "https://github.com/ryanoasis/nerd-fonts/releases/download/$Version/$Name.zip"
    $work    = Join-Path $env:TEMP "vimcode-font-$Name-$Version"
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regKey  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

    if ($DryRun) {
        Write-Note "would download $url and install per-user into $fontDir"
        Add-Result "font $Name" 'would install'
        return
    }

    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $work -Force
    $null = New-Item -ItemType Directory -Path $fontDir -Force
    if (-not (Test-Path $regKey)) { $null = New-Item -Path $regKey -Force }

    $zip = Join-Path $work "$Name.zip"
    Write-Host "    downloading $Name $Version ..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $work -Force

    Add-Type -AssemblyName System.Drawing
    $installed = 0
    $families  = New-Object System.Collections.Generic.HashSet[string]

    Get-ChildItem -Path $work -Include '*.ttf', '*.otf' -Recurse | ForEach-Object {
        $src  = $_
        $dest = Join-Path $fontDir $src.Name
        $kind = if ($src.Extension -ieq '.otf') { 'OpenType' } else { 'TrueType' }
        $entry = "$($src.BaseName) ($kind)"

        # Record the family name so we can tell the user what to select.
        try {
            $collection = New-Object System.Drawing.Text.PrivateFontCollection
            $collection.AddFontFile($src.FullName)
            [void] $families.Add($collection.Families[0].Name)
            $collection.Dispose()
        } catch {
            # Family probing is cosmetic; never let it stop the install.
        }

        Copy-Item -Path $src.FullName -Destination $dest -Force
        Set-ItemProperty -Path $regKey -Name $entry -Value $dest -Type String
        $installed++
    }

    # Make the fonts usable without a logoff/logon cycle.
    Register-FontsWithSession -Directory $fontDir

    Write-Ok "$installed font file(s) installed for the current user"
    if ($families.Count -gt 0) {
        Write-Ok "families available: $(($families | Sort-Object) -join ', ')"
    }
    Add-Result "font $Name" 'installed' "$installed files"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

function Register-FontsWithSession {
    param([string] $Directory)

    $signature = @"
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFileName);

[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam,
    IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
"@
    try {
        if (-not ('VimCode.FontApi' -as [type])) {
            Add-Type -MemberDefinition $signature -Namespace 'VimCode' -Name 'FontApi'
        }
        Get-ChildItem -Path $Directory -Include '*.ttf', '*.otf' -Recurse | ForEach-Object {
            [void] [VimCode.FontApi]::AddFontResourceW($_.FullName)
        }
        $result = [IntPtr]::Zero
        # HWND_BROADCAST = 0xffff, WM_FONTCHANGE = 0x001D, SMTO_ABORTIFHUNG = 0x0002
        [void] [VimCode.FontApi]::SendMessageTimeout(
            [IntPtr] 0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref] $result)
    } catch {
        Write-Note 'could not broadcast the font change; a re-login will pick it up'
    }
}

# --------------------------------------------------------------------------
# Windows Terminal
# --------------------------------------------------------------------------

function Remove-JsonComments {
    param([string] $Text)
    # Strip // and /* */ comments while leaving anything inside a string alone.
    $pattern = '("(\\.|[^"\\])*")|/\*[\s\S]*?\*/|//[^\r\n]*'
    return [regex]::Replace($Text, $pattern, {
        param($m) if ($m.Groups[1].Success) { $m.Value } else { '' }
    })
}

function Set-JsonProperty {
    param([psobject] $Object, [string] $Name, $Value)
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Set-WindowsTerminalFont {
    param([string] $Face)

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }

    if (-not $candidates) {
        Write-Note 'Windows Terminal settings.json not found -- set the font face by hand'
        Add-Result 'terminal font' 'skipped' 'no settings.json'
        return
    }

    foreach ($path in $candidates) {
        if ($DryRun) {
            Write-Note "would set profiles.defaults.font.face = '$Face' in $path"
            Add-Result 'terminal font' 'would set'
            continue
        }

        $raw = Get-Content -Path $path -Raw -Encoding UTF8
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            $json = (Remove-JsonComments $raw) | ConvertFrom-Json
        }

        if (-not $json.PSObject.Properties['profiles']) {
            Set-JsonProperty $json 'profiles' ([pscustomobject]@{})
        }
        if ($json.profiles -is [array]) {
            Write-Note "$path uses the legacy profiles array -- set the font by hand"
            Add-Result 'terminal font' 'skipped' 'legacy schema'
            continue
        }
        if (-not $json.profiles.PSObject.Properties['defaults']) {
            Set-JsonProperty $json.profiles 'defaults' ([pscustomobject]@{})
        }
        if (-not $json.profiles.defaults.PSObject.Properties['font']) {
            Set-JsonProperty $json.profiles.defaults 'font' ([pscustomobject]@{})
        }

        $current = $null
        if ($json.profiles.defaults.font.PSObject.Properties['face']) {
            $current = $json.profiles.defaults.font.face
        }
        if ($current -eq $Face) {
            Write-Skip "already set to '$Face' in $(Split-Path $path -Leaf)"
            Add-Result 'terminal font' 'present'
            continue
        }

        # ConvertTo-Json drops comments and reformats, so keep the original.
        $backup = "$path.vimcode-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $path -Destination $backup -Force

        Set-JsonProperty $json.profiles.defaults.font 'face' $Face
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8

        Write-Ok "font face set to '$Face'"
        if ($current) { Write-Note "previous value was '$current'" }
        Write-Note "backup: $backup (comments and formatting are not preserved)"
        Add-Result 'terminal font' 'set' $Face
    }
}

# --------------------------------------------------------------------------
# Neovim plugin bootstrap
# --------------------------------------------------------------------------

function Invoke-NvimHeadless {
    param([string] $Label, [string[]] $Commands)

    $configRoot = Split-Path -Parent $PSScriptRoot
    $initLua    = Join-Path $configRoot 'init.lua'

    # The file argument makes argc() non-zero, which stops autocmds.lua from
    # opening the session layout (explorer + terminals) part-way through a
    # long headless run.
    $nvimArgs = @('--headless', $initLua) + $Commands + @('+qa')

    Write-Host "    nvim $Label ..."
    & nvim @nvimArgs 2>&1 | ForEach-Object { Write-Host "      $_" }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "${Label}: done"
        Add-Result $Label 'done'
    } else {
        Write-Note "${Label}: nvim exited $LASTEXITCODE (usually harmless, check inside nvim)"
        Add-Result $Label 'check' "exit $LASTEXITCODE"
    }
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

Write-Host ''
Write-Host '  VimCode setup -- Windows' -ForegroundColor Magenta
if ($DryRun) { Write-Host '  (dry run: nothing will be changed)' -ForegroundColor Yellow }

if (-not (Test-Command 'winget')) {
    throw 'winget was not found. Install "App Installer" from the Microsoft Store, then re-run.'
}

if (-not $SkipPackages) {
    Write-Step 'Installing packages with winget'
    foreach ($package in $Packages) { Install-WingetPackage $package }

    Update-SessionPath
    Write-Step 'Installing Python tooling with uv'
    if ((Test-Command 'uv') -and -not $DryRun) {
        & uv tool update-shell 2>&1 | Out-Null
        Update-SessionPath
    }
    foreach ($tool in @('ty', 'ruff')) { Install-UvTool $tool }
} else {
    Write-Step 'Skipping packages (-SkipPackages)'
}

if (-not $SkipFont) {
    Write-Step "Installing the $NerdFont Nerd Font"
    Install-NerdFont -Name $NerdFont -Version $NerdFontVersion
} else {
    Write-Step 'Skipping font install (-SkipFont)'
}

if (-not $SkipTerminalFont) {
    Write-Step 'Pointing Windows Terminal at the Nerd Font'
    Set-WindowsTerminalFont -Face $FontFace
} else {
    Write-Step 'Skipping Windows Terminal config (-SkipTerminalFont)'
}

if (-not $SkipPluginSync -and -not $DryRun) {
    Update-SessionPath
    if (Test-Command 'nvim') {
        Write-Step 'Bootstrapping Neovim plugins (this takes a few minutes)'
        # install + restore, not sync: this pins plugins to lazy-lock.json
        # instead of updating them and rewriting the committed lockfile.
        Invoke-NvimHeadless 'plugin install' @('+Lazy! install', '+Lazy! restore')
        # Pre-empts the two items in the README's troubleshooting section.
        Invoke-NvimHeadless 'debugpy install' @('+MasonInstall debugpy')
        Invoke-NvimHeadless 'markdown-preview build' @('+Lazy! build markdown-preview.nvim')
    } else {
        Write-Note 'nvim is not on PATH yet -- reopen your shell and run: nvim'
    }
} else {
    Write-Step 'Skipping plugin bootstrap'
}

Write-Host ''
Write-Host '  Summary' -ForegroundColor Magenta
$script:Results | Format-Table -AutoSize

Write-Host '  Next steps:' -ForegroundColor Magenta
Write-Host '    1. Close and reopen your terminal so PATH and the font take effect.'
Write-Host '    2. If Windows Terminal still shows the old font, restart it.'
Write-Host "    3. Run 'nvim' and then ':checkhealth' to confirm everything is wired up."
Write-Host ''

if ($script:Results | Where-Object { $_.Status -eq 'FAILED' }) { exit 1 }
