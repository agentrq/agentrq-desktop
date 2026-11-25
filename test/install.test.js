// Copyright 2026 Contextual, Inc. https://agentrq.com
// This notice may not be modified or removed.
// SPDX-License-Identifier: AGPL-3.0-only

// Tests for install.sh, run under `sh` against a fake GitHub: `curl` and
// `uname` are stubs on PATH, everything else is real. The real release is
// installed end to end by .github/workflows/installers.yml.
// Run with `node --test test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.join(__dirname, '../install.sh');
const TAG = 'v1.2.3';
const DOWNLOAD = `https://github.com/agentrq/agentrq-desktop/releases/download/${TAG}`;
const BODY = 'the build';
const SHA = crypto.createHash('sha256').update(BODY).digest('hex');

// Serves the release JSON for API calls, writes BODY for a download, and logs
// every URL it was asked for.
const FAKE_CURL = `#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
	case "$1" in
	-o) out="$2"; shift 2 ;;
	-H) shift 2 ;;
	-*) shift ;;
	*) url="$1"; shift ;;
	esac
done
case "$url" in
*api.github.com*) echo "API $url" >> "$LOG"; cat "$RELEASE" ;;
*/icons/*) echo "ICON $url" >> "$LOG"; [ -n "$out" ] && printf png > "$out" ;;
*)
	echo "DOWNLOAD $url" >> "$LOG"
	[ -n "$out" ] && printf '%s' '${BODY}' > "$out"
	;;
esac
`;

const LINUX = ['AgentRQ-Tauri-1.2.3-x64.AppImage', 'AgentRQ-Tauri-1.2.3-x64.AppImage.sig', 'AgentRQ-Tauri-1.2.3-x64.deb', 'AgentRQ-Tauri-1.2.3-x64.exe'];
const MAC = ['AgentRQ-Tauri-1.2.3-arm64.dmg', 'AgentRQ-Tauri-1.2.3-x64.dmg', 'AgentRQ-Tauri-1.2.3-arm64.app.tar.gz'];

// GitHub's asset shape, uploader included, so the digest lookup is tested
// against the fields that really sit around it.
function assetJSON(name, digest) {
  return {
    url: `https://api.github.com/repos/agentrq/agentrq-desktop/releases/assets/${name.length}`,
    id: name.length,
    name,
    uploader: { login: 'github-actions[bot]', id: 41898282, url: 'https://api.github.com/users/github-actions%5Bbot%5D', type: 'Bot' },
    content_type: 'application/octet-stream',
    state: 'uploaded',
    size: 9,
    digest,
    browser_download_url: `${DOWNLOAD}/${name}`,
  };
}

function run({ arch = 'x86_64', osName = 'Linux', names = LINUX, digests = {}, args = [], env = {}, pretty = false, home } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'install-tauri-'));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  home = home || path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(path.join(bin, 'curl'), FAKE_CURL, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, 'uname'), `#!/bin/sh\ncase "$1" in -s) echo ${osName} ;; -m) echo ${arch} ;; esac\n`, { mode: 0o755 });
  const release = {
    tag_name: TAG,
    author: { login: 'someone', url: 'https://api.github.com/users/someone' },
    assets: names.map((n) => assetJSON(n, n in digests ? digests[n] : `sha256:${SHA}`)),
  };
  const releaseFile = path.join(root, 'release.json');
  fs.writeFileSync(releaseFile, pretty ? JSON.stringify(release, null, 2) : JSON.stringify(release));
  const log = path.join(root, 'log');
  fs.writeFileSync(log, '');
  const r = spawnSync('sh', [SCRIPT, ...args], {
    env: { HOME: home, PATH: `${bin}:/usr/bin:/bin`, RELEASE: releaseFile, LOG: log, TMPDIR: root, ...env },
    encoding: 'utf8',
  });
  const lines = fs.readFileSync(log, 'utf8').split('\n').filter(Boolean);
  return {
    r,
    home,
    apis: lines.filter((l) => l.startsWith('API ')),
    downloads: lines.filter((l) => l.startsWith('DOWNLOAD ')),
    icons: lines.filter((l) => l.startsWith('ICON ')),
  };
}

const installed = (home) => path.join(home, '.local', 'bin', 'agentrq-tauri');

for (const pretty of [false, true]) {
  test(`Linux x64: installs the AppImage, verified (${pretty ? 'pretty' : 'compact'} JSON)`, () => {
    const { r, home, downloads, apis } = run({ pretty });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(apis, ['API https://api.github.com/repos/agentrq/agentrq-desktop/releases/latest']);
    assert.deepEqual(downloads, [`DOWNLOAD ${DOWNLOAD}/AgentRQ-Tauri-1.2.3-x64.AppImage`]);
    assert.match(r.stdout, /Checksum verified\./);
    assert.equal(fs.readFileSync(installed(home), 'utf8'), BODY);
    assert.equal(fs.statSync(installed(home)).mode & 0o777, 0o755);
    assert.equal(fs.readFileSync(path.join(home, '.local', 'bin', '.agentrq-tauri-version'), 'utf8'), '1.2.3\n');
  });
}

test('Linux: a checksum mismatch installs nothing', () => {
  const { r, home } = run({ digests: { 'AgentRQ-Tauri-1.2.3-x64.AppImage': `sha256:${'0'.repeat(64)}` } });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /checksum mismatch/);
  assert.equal(fs.existsSync(installed(home)), false);
});

test("Linux: another asset's digest is never used for the AppImage", () => {
  // The asset before it carries a digest, the AppImage none.
  const names = ['AgentRQ-Tauri-1.2.3-x64.deb', 'AgentRQ-Tauri-1.2.3-x64.AppImage'];
  const { r } = run({ names, digests: { 'AgentRQ-Tauri-1.2.3-x64.deb': `sha256:${'0'.repeat(64)}`, 'AgentRQ-Tauri-1.2.3-x64.AppImage': null } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /GitHub lists no checksum/);
});

test('Linux: an upper-case digest still matches', () => {
  const { r } = run({ digests: { 'AgentRQ-Tauri-1.2.3-x64.AppImage': `sha256:${SHA.toUpperCase()}` } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Checksum verified\./);
});

test('Linux: writes the launcher entry and fetches the icons at the tag', () => {
  const { r, home, icons } = run();
  assert.equal(r.status, 0, r.stderr);
  const desktop = fs.readFileSync(path.join(home, '.local', 'share', 'applications', 'agentrq-tauri.desktop'), 'utf8');
  assert.equal(desktop, [
    '[Desktop Entry]',
    'Type=Application',
    'Name=AgentRQ Tauri',
    'Comment=Task orchestration for coding agents',
    `Exec=${installed(home)} %u`,
    'Icon=agentrq-tauri',
    'Terminal=false',
    'Categories=Development;',
    'MimeType=x-scheme-handler/agentrq-tauri;',
    'StartupWMClass=agentrq-tauri',
    '',
  ].join('\n'));
  assert.deepEqual(icons, [
    `ICON https://raw.githubusercontent.com/agentrq/agentrq-desktop/${TAG}/src/tauri/src-tauri/icons/icon.png`,
    `ICON https://raw.githubusercontent.com/agentrq/agentrq-desktop/${TAG}/src/tauri/src-tauri/icons/128x128@2x.png`,
  ]);
});

test('Linux: the same version again is a no-op, and --force reinstalls', () => {
  const first = run();
  assert.equal(first.r.status, 0, first.r.stderr);
  const again = run({ home: first.home });
  assert.equal(again.r.status, 0);
  assert.match(again.r.stdout, /already installed/);
  assert.deepEqual(again.downloads, []);
  const forced = run({ home: first.home, args: ['--force'] });
  assert.equal(forced.r.status, 0, forced.r.stderr);
  assert.equal(forced.downloads.length, 1);
});

test('Linux: --dir installs elsewhere', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'install-tauri-dir-'));
  const { r } = run({ args: ['--dir', dir] });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(fs.readFileSync(path.join(dir, 'agentrq-tauri'), 'utf8'), BODY);
});

test('Linux arm64: refused while no arm64 AppImage is released', () => {
  const { r, downloads } = run({ arch: 'aarch64' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /no Linux arm64 AppImage/);
  assert.deepEqual(downloads, []);
});

test('Linux arm64: picks the arm64 AppImage once there is one', () => {
  const names = ['AgentRQ-Tauri-1.2.3-x64.AppImage', 'AgentRQ-Tauri-1.2.3-arm64.AppImage'];
  const { downloads } = run({ arch: 'aarch64', names });
  assert.deepEqual(downloads, [`DOWNLOAD ${DOWNLOAD}/AgentRQ-Tauri-1.2.3-arm64.AppImage`]);
});

for (const version of ['v0.19.4', '0.19.4']) {
  test(`--version ${version} asks for tag v0.19.4`, () => {
    const { apis } = run({ args: ['--version', version] });
    assert.deepEqual(apis, ['API https://api.github.com/repos/agentrq/agentrq-desktop/releases/tags/v0.19.4']);
  });
}

test('AGENTRQ_VERSION is the same as --version', () => {
  const { apis } = run({ env: { AGENTRQ_VERSION: '0.19.4' } });
  assert.deepEqual(apis, ['API https://api.github.com/repos/agentrq/agentrq-desktop/releases/tags/v0.19.4']);
});

// macOS cannot install here (no hdiutil), so these stop after the download:
// what matters is which dmg it fetched.
for (const [arch, want] of [['arm64', 'AgentRQ-Tauri-1.2.3-arm64.dmg'], ['x86_64', 'AgentRQ-Tauri-1.2.3-x64.dmg']]) {
  test(`macOS ${arch}: downloads the ${arch} dmg`, () => {
    const { downloads } = run({ osName: 'Darwin', arch, names: MAC });
    assert.deepEqual(downloads, [`DOWNLOAD ${DOWNLOAD}/${want}`]);
  });
}

test('Windows is pointed at install.ps1', () => {
  const { r, apis } = run({ osName: 'MINGW64_NT-10.0' });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /install\.ps1/);
  assert.deepEqual(apis, []);
});

test('an unknown flag is refused', () => {
  const { r } = run({ args: ['--tauri'] });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /unknown option: --tauri/);
});

test('--help prints usage', () => {
  const { r, apis } = run({ args: ['--help'] });
  assert.equal(r.status, 0);
  assert.match(r.stdout, /Usage: install\.sh/);
  assert.deepEqual(apis, []);
});
