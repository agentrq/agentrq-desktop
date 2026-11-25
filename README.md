# AgentRQ Desktop (Tauri)

The [AgentRQ](https://agentrq.com) desktop app on [Tauri](https://tauri.app),
a preview beside the Electron app in
[agentrq/agentrq](https://github.com/agentrq/agentrq). It renders the same UI,
built from agentrq's frontend, which this repository pins as the `src/agentrq`
submodule.

## Install

Builds are on the [releases](https://github.com/agentrq/agentrq-desktop/releases)
page, named `AgentRQ-Tauri-<version>-<arch>.<ext>`. The install scripts
below pick the right one, check it against the SHA-256 GitHub records for it,
and install it. Once installed, the app updates itself from those releases.

Every script takes `--version <tag>` (`-Version` on Windows, or
`AGENTRQ_VERSION` anywhere) to install a given release, and `--help`.

The same installs are on agentrq.com, whose scripts also install the Electron
app when you leave out the Tauri switch:

```sh
curl -fsSL https://agentrq.com/install.sh | sh -s -- --tauri          # macOS, Linux
```

```powershell
$env:AGENTRQ_TAURI = '1'; irm https://agentrq.com/install.ps1 | iex   # Windows
```

### macOS (Apple silicon and Intel)

```sh
curl -fsSL https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.sh | sh
```

This installs `AgentRQ Tauri.app` into `/Applications` (or
`~/Applications` when that is not writable); open it with
`open -a 'AgentRQ Tauri'`. Run the same command again to update. If the app
is running, add `-s -- --quit` to have the script close it first.

Or download the `.dmg` for your Mac (`arm64` for Apple silicon, `x64` for
Intel), open it and drag **AgentRQ Tauri** into Applications. The build is not
notarized yet, so macOS refuses to open a copy downloaded with a browser until
you clear its quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/AgentRQ Tauri.app"
```

The install script needs no such step.

### Linux (x64)

```sh
curl -fsSL https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.sh | sh
```

This installs the AppImage as `~/.local/bin/agentrq-tauri`, with a launcher
entry, and needs no root. Run the same command again to update. Pass
`--dir <path>` to install elsewhere.

Or, on Debian and Ubuntu, install the `.deb`, which also pulls in its
dependencies:

```sh
sudo apt install ./AgentRQ-Tauri-<version>-x64.deb
```

Or run the `.AppImage` directly after `chmod +x`. AppImages need FUSE 2:
`sudo apt install libfuse2t64` on Ubuntu 24.04 and later, `libfuse2` on 22.04.

There is no Linux arm64 build yet.

### Windows (x64)

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.ps1 | iex
```

Run the same command again to update. If the app is running, set
`$env:AGENTRQ_QUIT = '1'` first to have the script close it.

Or download `AgentRQ-Tauri-<version>-x64.exe` and run it. Either way it
installs for the current user only, so it needs no administrator rights, and
adds a Start menu entry. If SmartScreen warns about an unrecognised app, choose **More info** →
**Run anyway**. Uninstall it from **Settings → Apps**.

## Build from source

Building, testing and the verify scripts: [`src/tauri/README.md`](src/tauri/README.md).

## Versions

This repository takes its version numbers from
[agentrq/agentrq](https://github.com/agentrq/agentrq), not from its own
changes, and it skips some agentrq releases on purpose. So its versions do
not follow semantic versioning on their own, and some versions are missing
from this repository's releases.

## License

[AGPL-3.0-only](LICENSE).
