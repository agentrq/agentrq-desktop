# AgentRQ Desktop (Tauri)

The [AgentRQ](https://agentrq.com) desktop app on [Tauri](https://tauri.app),
a preview beside the Electron app in
[agentrq/agentrq](https://github.com/agentrq/agentrq). It renders the same UI,
built from agentrq's frontend, which this repository pins as the `src/agentrq`
submodule.

Install on macOS or Linux:

```sh
curl -fsSL https://agentrq.com/install.sh | sh -s -- --tauri
```

or download an `AgentRQ-Tauri-*` build from the
[releases](https://github.com/agentrq/agentrq-desktop/releases).

Building, testing and the verify scripts: [`src/tauri/README.md`](src/tauri/README.md).

## Versions

This repository takes its version numbers from
[agentrq/agentrq](https://github.com/agentrq/agentrq), not from its own
changes, and it skips some agentrq releases on purpose. So its versions do
not follow semantic versioning on their own, and some versions are missing
from this repository's releases.

## License

[AGPL-3.0-only](LICENSE).
