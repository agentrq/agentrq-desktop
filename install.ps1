# Copyright 2026 Contextual, Inc. https://agentrq.com
# This notice may not be modified or removed.
# SPDX-License-Identifier: AGPL-3.0-only
#
# AgentRQ Tauri installer and updater for Windows.
#
#   irm https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.ps1 | iex
#
# The same command installs and updates: it resolves the newest release of this
# repository, downloads the setup program, checks it against the SHA-256 digest
# GitHub records for the asset, and runs it silently. The setup program
# installs for the current user, so no administrator rights are needed.
#
# Piped in with `irm | iex`, this script cannot see command-line flags. Set the
# equivalent environment variable first:
#
#   $env:AGENTRQ_VERSION = 'v0.19.4'; irm https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.ps1 | iex
#
# Run as a file, ordinary parameters work:
#
#   .\install.ps1 -Version v0.19.4 -Quit -Force
#
# Flags / environment variables:
#
#   -Version <tag>   / AGENTRQ_VERSION   install a specific release, e.g. v0.19.4
#   -Quit            / AGENTRQ_QUIT      close a running AgentRQ Tauri instead of refusing
#   -Force           / AGENTRQ_FORCE     reinstall even when the installed version already matches
#   -Help
#
# GITHUB_TOKEN, if set, is used for the API call.

param(
    [string]$Version = $env:AGENTRQ_VERSION,
    [switch]$Quit = [bool]$env:AGENTRQ_QUIT,
    [switch]$Force = [bool]$env:AGENTRQ_FORCE,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
# Invoke-WebRequest's progress bar slows a large download by an order of magnitude
# on Windows PowerShell 5.1.
$ProgressPreference = 'SilentlyContinue'

$Repo = 'agentrq/agentrq-desktop'
$Api = "https://api.github.com/repos/$Repo/releases"
$ReleasesPage = "https://github.com/$Repo/releases"
$Product = 'AgentRQ Tauri'
$ProcessName = 'agentrq-tauri'
$UpdateCmd = "irm https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex"

function Say([string]$Message) { Write-Host $Message }
function Note([string]$Message) { Write-Host "  $Message" }
# A throw, never `exit`: under `irm | iex` this runs in the caller's own
# session, and `exit` would close their PowerShell window.
function Die([string]$Message) { throw "error: $Message" }

function Install-AgentRQTauri {
    if ($Help) {
        Write-Host @'
AgentRQ Tauri installer and updater, for Windows.

  install.ps1 [-Version <tag>] [-Quit] [-Force]

  -Version <tag>   install a specific release, e.g. v0.19.4
  -Quit            close a running AgentRQ Tauri instead of refusing
  -Force           reinstall even when the installed version already matches
  -Help            this

Environment: AGENTRQ_VERSION, AGENTRQ_QUIT, AGENTRQ_FORCE, GITHUB_TOKEN
'@
        return
    }

    # The setup program's own uninstall entry, under the current user.
    function Get-InstalledVersion {
        $keys = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $entry = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($entry -and $entry.DisplayName -eq $Product) { return [string]$entry.DisplayVersion }
        }
        return $null
    }

    # ---------------------------------------------------------------- the machine

    # Windows on Arm runs the x64 build under emulation until an arm64 one ships.
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { $arches = @('x64') }
        'ARM64' { $arches = @('arm64', 'x64') }
        default { Die "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE). See $ReleasesPage" }
    }

    # --------------------------------------------------------------- the release

    $headers = @{ 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }

    if ($Version) {
        $tagName = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
        $apiUrl = "$Api/tags/$tagName"
    }
    else {
        $apiUrl = "$Api/latest"
    }

    Say "Looking up the $Product release..."
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
    }
    catch {
        Die "could not fetch $apiUrl -- no such release, or GitHub is unreachable"
    }
    $tag = $release.tag_name
    if (-not $tag) { Die "no published release found at $apiUrl" }
    $version = $tag -replace '^v', ''

    # Release assets are named AgentRQ-Tauri-<version>-<arch>.exe.
    $asset = $null
    foreach ($arch in $arches) {
        $asset = $release.assets | Where-Object { $_.name -match "-$arch\.exe$" } | Select-Object -First 1
        if ($asset) { break }
    }
    if (-not $asset) { Die "release $tag has no Windows installer for $($arches[0]). See $ReleasesPage" }
    $filename = $asset.name

    # ------------------------------------------------------- already up to date?

    if (-not $Force) {
        $installed = Get-InstalledVersion
        if ($installed -and $installed -eq $version) {
            Say "$Product $version is already installed. Nothing to do."
            Note 'Reinstall anyway with -Force.'
            return
        }
    }

    # The setup program cannot replace files a running app holds open.
    $running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($running) {
        if (-not $Quit) {
            Die "$Product is running. Quit it and run this again, or set `$env:AGENTRQ_QUIT = '1' (or pass -Quit) to have the installer close it."
        }
        Say "Quitting $Product..."
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        $running | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
        if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
            Die "$Product did not quit. Close it manually and run this again."
        }
    }

    # ----------------------------------------------------------------- download

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "agentrq-tauri-install-$([System.IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        $downloadPath = Join-Path $tmpDir $filename
        Say "Downloading $filename..."
        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
        }
        catch {
            Die "download failed: $($asset.browser_download_url)"
        }

        # GitHub records each asset's SHA-256 as "sha256:<hex>".
        if ($asset.digest -and $asset.digest -match '^sha256:([0-9a-fA-F]{64})$') {
            $expected = $Matches[1].ToLower()
            $actual = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $expected) {
                Die "checksum mismatch for $filename -- the download is corrupt or has been tampered with. Nothing was installed."
            }
            Note 'Checksum verified.'
        }
        else {
            Note "GitHub lists no checksum for $filename; skipping verification."
        }

        # ---------------------------------------------------------------- install

        Say "Installing $Product $version..."
        $setup = Start-Process -FilePath $downloadPath -ArgumentList '/S' -Wait -PassThru
        if ($setup.ExitCode -ne 0) {
            Die "the setup program exited with code $($setup.ExitCode)"
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    $installed = Get-InstalledVersion
    if ($installed -ne $version) {
        Die "the setup program finished, but $Product $version is not listed as installed (found: $installed)"
    }

    Say ""
    Say "$Product $version installed for this user."
    Note "Launch it from the Start menu: $Product"
    Say ""
    Say 'Update later by running the same command:'
    Say "  $UpdateCmd"
}

Install-AgentRQTauri
