# AgentRQ Desktop: codebase notes

The AgentRQ desktop app on Tauri (preview; Electron, in
[agentrq/agentrq](https://github.com/agentrq/agentrq), is still the default).

## Layout

- `src/tauri/` — the app: `core/` is pure Rust, `src-tauri/` the shell, `src/`
  the `window.agentrq` bridge, the guest script and the extension host.
- `src/agentrq/` — agentrq/agentrq as a **pinned git submodule**. The renderer
  is its `desktop/src/renderer` built from its `frontend/src`, the extension
  host runs its `desktop/src/main/extensions` unchanged, the tests run its
  `examples/extensions`, and the verify scripts build its `backend/`. A path
  such as `desktop/…` or `frontend/…` in the notes means `src/agentrq/…`.
  Never edit it here: change agentrq, then move the pin in a pull request.
- `docs/agents/` — the notes.

## The notes

> **Open the note before you change the code.** Each one records decisions
> that are invisible in the source. Keep them short.

- **[Tauri desktop app](docs/agents/desktop-tauri.md)** — where pure logic
  goes, how a bridge command is named, and the WebKit, WebView2 and WKWebView
  traps. Its [parity checklist](docs/agents/desktop-tauri-parity.md) says what
  proves each feature on each OS; update a row with the change that moves it.
- agentrq's [desktop note](https://github.com/agentrq/agentrq/blob/main/docs/agents/desktop.md)
  — the renderer is shared with Electron, so its rules hold here too.

## Rules

- **Releases are the update feed.** A `v*` tag on main builds every platform
  into a draft, writes `latest-tauri.json`, then publishes. The four version
  stamps must agree with the tag (`node src/tauri/scripts/check-versions.mjs`).
  Apps installed before the move poll agentrq/agentrq's releases, whose release
  workflow copies `latest-tauri.json` from here; keep that feed's name and the
  `AgentRQ-Tauri-*` asset names.
- **A new dependency starts at its latest release**, with that as its floor.
- Every source file carries the AGPL-3.0-only header.

## Running tests

```bash
git submodule update --init
(cd src/agentrq/frontend && npm ci)
cd src/tauri && npm ci && npm run test:coverage && npm run test:rust
```

## Commit and pull request convention

Include `Task: <taskID>` in the commit body. A pull request description says
what changed, why, the test coverage of the new lines and the effect on the
total, and ends with
`Generated with [AgentRQ](https://agentrq.com) for TaskID: <taskID>`.
