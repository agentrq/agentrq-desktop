#!/bin/sh
# Copyright 2026 Contextual, Inc. https://agentrq.com
# This notice may not be modified or removed.
# SPDX-License-Identifier: AGPL-3.0-only
#
# AgentRQ Tauri installer and updater for macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.sh | sh
#
# The same command installs and updates: it resolves the newest release of this
# repository, downloads the build for this machine, checks it against the
# SHA-256 digest GitHub records for the asset, and swaps it into place.
#
# Constraints worth knowing before editing:
#
#   * POSIX sh only. Piped into `sh` this runs under dash on most Linux
#     systems, so bashisms ([[ ]], arrays, local) are out.
#   * Nothing may read stdin. With `curl ... | sh` the script *is* stdin, so
#     every choice is a flag or an environment variable, never a prompt.
#   * ASCII only. macOS's /bin/sh is bash 3.2, which folds a UTF-8 byte after
#     "$name" into the variable name and dies under `set -u`.
#
# Flags (pipe them through as: curl -fsSL ... | sh -s -- --quit)
#
#   --version <tag>   install a specific release, e.g. v0.19.4
#   --dir <path>      install location (default /Applications, ~/.local/bin)
#   --quit            on macOS, quit a running AgentRQ Tauri instead of refusing
#   --force           reinstall even when the current version already matches
#   --help
#
# Equivalent environment variables: AGENTRQ_VERSION, AGENTRQ_INSTALL_DIR,
# AGENTRQ_QUIT, AGENTRQ_FORCE. GITHUB_TOKEN, if set, is used for the API call.

set -eu

REPO="agentrq/agentrq-desktop"
API="https://api.github.com/repos/$REPO/releases"
RELEASES_PAGE="https://github.com/$REPO/releases"
RAW="https://raw.githubusercontent.com/$REPO"

APP_PRODUCT="AgentRQ Tauri"
APP_BUNDLE="AgentRQ Tauri.app"
BIN_NAME="agentrq-tauri"
DESKTOP_FILE="agentrq-tauri.desktop"
MARKER_FILE=".agentrq-tauri-version"
SCHEME="agentrq-tauri"
UPDATE_CMD="curl -fsSL $RAW/main/install.sh | sh"

VERSION="${AGENTRQ_VERSION:-}"
INSTALL_DIR="${AGENTRQ_INSTALL_DIR:-}"
QUIT="${AGENTRQ_QUIT:-}"
FORCE="${AGENTRQ_FORCE:-}"

# Set once a disk image is attached, so the exit trap can detach it.
MOUNTPOINT=""
TMPDIR_=""

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
AgentRQ Tauri installer and updater, for macOS and Linux.

Usage: install.sh [--version <tag>] [--dir <path>] [--quit] [--force]

  curl -fsSL https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/agentrq/agentrq-desktop/main/install.sh | sh -s -- --quit

  --version <tag>   install a specific release, e.g. v0.19.4
  --dir <path>      install location (default /Applications, ~/.local/bin)
  --quit            on macOS, quit a running AgentRQ Tauri instead of refusing
  --force           reinstall even when the current version already matches
EOF
}

cleanup() {
	# Detach first: macOS will not remove a directory an image is attached to.
	if [ -n "$MOUNTPOINT" ]; then
		hdiutil detach "$MOUNTPOINT" -quiet >/dev/null 2>&1 || true
	fi
	if [ -n "$TMPDIR_" ]; then
		rm -rf "$TMPDIR_"
	fi
}
trap cleanup EXIT INT TERM

while [ $# -gt 0 ]; do
	case "$1" in
	--version)
		[ $# -ge 2 ] || die "--version needs a tag, e.g. --version v0.19.4"
		VERSION="$2"
		shift 2
		;;
	--dir)
		[ $# -ge 2 ] || die "--dir needs a path"
		INSTALL_DIR="$2"
		shift 2
		;;
	--quit)
		QUIT=1
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
done

command -v curl >/dev/null 2>&1 || die "curl is required"

# ---------------------------------------------------------------- the machine

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
Darwin) platform="mac" ;;
Linux) platform="linux" ;;
*)
	# Windows has install.ps1, beside this script.
	die "unsupported system: $os. On Windows, run install.ps1 from PowerShell, or download the installer from $RELEASES_PAGE"
	;;
esac

case "$arch" in
arm64 | aarch64) arch="arm64" ;;
x86_64 | amd64 | x64) arch="x64" ;;
*) die "unsupported architecture: $arch. See $RELEASES_PAGE" ;;
esac

# --------------------------------------------------------------- the release

if [ -n "$VERSION" ]; then
	case "$VERSION" in
	v*) api_url="$API/tags/$VERSION" ;;
	*) api_url="$API/tags/v$VERSION" ;;
	esac
else
	api_url="$API/latest"
fi

say "Looking up the $APP_PRODUCT release..."
if [ -n "${GITHUB_TOKEN:-}" ]; then
	release="$(curl -fsSL -H 'Accept: application/vnd.github+json' -H "Authorization: Bearer $GITHUB_TOKEN" "$api_url" </dev/null)" ||
		die "could not fetch $api_url -- no such release, or GitHub is unreachable"
else
	release="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api_url" </dev/null)" ||
		die "could not fetch $api_url -- no such release, or GitHub is unreachable"
fi

# grep and sed rather than a JSON parser: jq is not installable from here, and
# this only has to survive GitHub's own formatting, pretty-printed or compact.
tag="$(printf '%s' "$release" | grep -o '"tag_name": *"[^"]*"' | head -n 1 |
	sed 's/^[^:]*: *"//; s/"$//' || true)"
[ -n "$tag" ] || die "no published release found at $api_url"
version="${tag#v}"

assets="$(printf '%s' "$release" |
	grep -o '"browser_download_url": *"[^"]*"' |
	sed 's/^[^:]*: *"//; s/"$//' || true)"

# Release assets are named AgentRQ-Tauri-<version>-<arch>.<ext>.
if [ "$platform" = "mac" ]; then
	kind="disk image"
	candidates="$(printf '%s\n' "$assets" | grep -i '\.dmg$' || true)"
else
	# AppImage over deb: no root needed, and it runs on any distribution.
	kind="AppImage"
	candidates="$(printf '%s\n' "$assets" | grep -i '\.AppImage$' || true)"
fi
if [ "$arch" = "arm64" ]; then
	asset="$(printf '%s\n' "$candidates" | grep -i -e 'arm64' -e 'aarch64' | head -n 1 || true)"
else
	asset="$(printf '%s\n' "$candidates" | grep -i -e 'x64' -e 'x86_64' -e 'amd64' | head -n 1 || true)"
fi
[ -n "$asset" ] || die "release $tag has no $os $arch $kind. See $RELEASES_PAGE"

filename="${asset##*/}"

# GitHub records each asset's SHA-256 as "digest": "sha256:<hex>", listed
# before the asset's browser_download_url. Split on commas so each field is a
# line, remember the digest of the asset being read, and print it at the URL
# we want. content_type comes first in every asset, so a digest never leaks
# from one asset into the next.
expected="$(printf '%s' "$release" | tr ',' '\n' | awk -v want="$asset" '
	/"content_type":/ { digest = "" }
	/"digest": *"sha256:/ { d = $0; sub(/.*"sha256:/, "", d); sub(/".*/, "", d); digest = d }
	/"browser_download_url":/ {
		u = $0; sub(/.*"browser_download_url": *"/, "", u); sub(/".*/, "", u)
		if (u == want) { print digest; exit }
	}
' || true)"

# ------------------------------------------------------- already up to date?

if [ -z "$FORCE" ]; then
	installed=""
	if [ "$platform" = "mac" ]; then
		probe="${INSTALL_DIR:-/Applications}/$APP_BUNDLE"
		[ -d "$probe" ] || probe="$HOME/Applications/$APP_BUNDLE"
		if [ -d "$probe" ]; then
			installed="$(defaults read "$probe/Contents/Info" \
				CFBundleShortVersionString 2>/dev/null || true)"
		fi
	else
		# An AppImage does not report its version without being run, so the
		# installer records what it wrote alongside the binary.
		marker="${INSTALL_DIR:-$HOME/.local/bin}/$MARKER_FILE"
		if [ -f "$marker" ]; then
			installed="$(cat "$marker" 2>/dev/null || true)"
		fi
	fi

	if [ -n "$installed" ] && [ "$installed" = "$version" ]; then
		say "$APP_PRODUCT $version is already installed. Nothing to do."
		note "Reinstall anyway with --force."
		exit 0
	fi
fi

# ----------------------------------------------------------------- download

TMPDIR_="$(mktemp -d "${TMPDIR:-/tmp}/agentrq-tauri.XXXXXX")"
download="$TMPDIR_/$filename"

say "Downloading $filename..."
curl -fL --progress-bar -o "$download" "$asset" </dev/null ||
	die "download failed: $asset"

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{ print $1 }'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$1" | awk '{ print $NF }'
	fi
}

if [ -z "$expected" ]; then
	note "GitHub lists no checksum for $filename; skipping verification."
else
	actual="$(sha256_of "$download" | tr 'A-F' 'a-f')"
	if [ -z "$actual" ]; then
		note "No SHA-256 tool found; skipping checksum verification."
	elif [ "$actual" != "$(printf '%s' "$expected" | tr 'A-F' 'a-f')" ]; then
		die "checksum mismatch for $filename -- the download is corrupt or has been tampered with. Nothing was installed."
	else
		note "Checksum verified."
	fi
fi

# ------------------------------------------------------------------ install

if [ "$platform" = "mac" ]; then
	dest_dir="$INSTALL_DIR"
	if [ -z "$dest_dir" ]; then
		# A managed Mac can have a read-only /Applications; a per-user install
		# is the working fallback rather than a failure.
		if [ -w /Applications ]; then
			dest_dir="/Applications"
		else
			dest_dir="$HOME/Applications"
		fi
	fi
	mkdir -p "$dest_dir"
	[ -w "$dest_dir" ] || die "$dest_dir is not writable. Pass --dir <path> to install elsewhere."

	app="$dest_dir/$APP_BUNDLE"

	# Replacing the bundle under a running app breaks its later launches.
	if pgrep -f "/$APP_BUNDLE/Contents/MacOS/" >/dev/null 2>&1; then
		[ -n "$QUIT" ] || die "$APP_PRODUCT is running. Quit it and run this again, or pass --quit to have the installer close it."
		say "Quitting $APP_PRODUCT..."
		osascript -e "quit app \"$APP_PRODUCT\"" >/dev/null 2>&1 || true
		waited=0
		while pgrep -f "/$APP_BUNDLE/Contents/MacOS/" >/dev/null 2>&1; do
			[ "$waited" -lt 15 ] || die "$APP_PRODUCT did not quit. Close it manually and run this again."
			sleep 1
			waited=$((waited + 1))
		done
	fi

	say "Installing to $app..."
	MOUNTPOINT="$TMPDIR_/mnt"
	mkdir -p "$MOUNTPOINT"
	# macOS 15 deprecates `hdiutil attach` for `diskutil image attach`; older
	# systems answer the new verb with "Unrecognized verb".
	if diskutil image </dev/null 2>&1 | grep -qi 'unrecognized verb'; then
		hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNTPOINT" \
			"$download" >/dev/null </dev/null || die "could not open $filename"
	else
		diskutil image attach --mountOptions nobrowse --readOnly --mountPoint "$MOUNTPOINT" \
			"$download" >/dev/null </dev/null || die "could not open $filename"
	fi

	src_app="$(find "$MOUNTPOINT" -maxdepth 1 -name '*.app' 2>/dev/null | head -n 1 || true)"
	[ -n "$src_app" ] || die "no application found inside $filename"

	# Stage the copy on the same volume, then swap, so an interrupted copy or a
	# full disk never leaves the machine without the app.
	staging="$dest_dir/.$APP_BUNDLE.incoming.$$"
	rm -rf "$staging"
	cp -R "$src_app" "$staging" || die "could not copy the application into $dest_dir"

	rm -rf "$app"
	mv "$staging" "$app"

	hdiutil detach "$MOUNTPOINT" -quiet >/dev/null 2>&1 || true
	MOUNTPOINT=""

	say ""
	say "$APP_PRODUCT $version installed to $app"
	note "Launch it with: open -a '$APP_PRODUCT'"
else
	bindir="${INSTALL_DIR:-$HOME/.local/bin}"
	mkdir -p "$bindir"
	[ -w "$bindir" ] || die "$bindir is not writable. Pass --dir <path> to install elsewhere."

	target="$bindir/$BIN_NAME"
	staging="$target.incoming.$$"

	say "Installing to $target..."
	cp "$download" "$staging"
	chmod 755 "$staging"
	mv "$staging" "$target"
	printf '%s\n' "$version" >"$bindir/$MARKER_FILE"

	# The launcher's icon, from this repository at the release's tag. Best
	# effort: a missing icon is cosmetic, never a reason to fail the install.
	icons_dir="$HOME/.local/share/icons/hicolor"
	icon_ok=""
	for size in 512x512 256x256; do
		case "$size" in
		512x512) src_icon="icon.png" ;;
		*) src_icon="128x128@2x.png" ;;
		esac
		if mkdir -p "$icons_dir/$size/apps" 2>/dev/null &&
			curl -fsL -o "$icons_dir/$size/apps/$BIN_NAME.png" \
				"$RAW/$tag/src/tauri/src-tauri/icons/$src_icon" </dev/null; then
			icon_ok=1
		else
			rm -f "$icons_dir/$size/apps/$BIN_NAME.png"
		fi
	done
	if [ -n "$icon_ok" ]; then
		gtk-update-icon-cache -f -t "$icons_dir" >/dev/null 2>&1 || true
	else
		note "Could not fetch the application icon; the launcher will show a generic one."
	fi

	# A launcher entry, and with it the agentrq-tauri:// handler that sign-in
	# returns through.
	apps_dir="$HOME/.local/share/applications"
	mkdir -p "$apps_dir"
	cat >"$apps_dir/$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_PRODUCT
Comment=Task orchestration for coding agents
Exec=$target %u
Icon=$BIN_NAME
Terminal=false
Categories=Development;
MimeType=x-scheme-handler/$SCHEME;
StartupWMClass=$BIN_NAME
EOF
	update-desktop-database "$apps_dir" >/dev/null 2>&1 || true

	say ""
	say "$APP_PRODUCT $version installed to $target"

	case ":$PATH:" in
	*":$bindir:"*) note "Launch it with: $BIN_NAME" ;;
	*)
		note "$bindir is not on your PATH. Add this to your shell profile:"
		note "  export PATH=\"$bindir:\$PATH\""
		;;
	esac
fi

say ""
say "Update later by running the same command:"
say "  $UPDATE_CMD"
