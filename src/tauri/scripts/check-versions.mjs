// Copyright 2026 Contextual, Inc. https://agentrq.com
// This notice may not be modified or removed.
// SPDX-License-Identifier: AGPL-3.0-only

/**
 * Fail the build when the app's four version stamps disagree, or when the tag
 * being released (GITHUB_REF) is not the version they carry. The updater
 * compares the version against the feed: a build stamped lower than its own
 * release would offer to update to itself, forever.
 *
 *   node scripts/check-versions.mjs
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

/** Where each version lives, relative to this app's folder. */
export const VERSION_FILES = ['package.json', 'src-tauri/tauri.conf.json', 'src-tauri/Cargo.toml', 'core/Cargo.toml']

/** The package's own version from a Cargo.toml: only the `[package]` table counts. */
export function cargoVersion(contents) {
  let inPackage = false
  for (const raw of contents.split('\n')) {
    const line = raw.trim()
    if (line.startsWith('[')) inPackage = line === '[package]'
    else if (inPackage) {
      const match = /^version\s*=\s*"([^"]+)"/.exec(line)
      if (match) return match[1]
    }
  }
  return null
}

/** The version a file carries, or null. */
export function versionOf(file, contents) {
  if (file.endsWith('.toml')) return cargoVersion(contents)
  try {
    const version = JSON.parse(contents).version
    return typeof version === 'string' && version !== '' ? version : null
  } catch {
    return null
  }
}

/** The problems with these files' versions and the tag, empty when there are none. */
export function check(contents, ref = '') {
  const versions = VERSION_FILES.map((file) => [file, versionOf(file, contents[file] ?? '')])
  const problems = versions.filter(([, v]) => v === null).map(([file]) => `${file} has no version`)
  const found = new Set(versions.map(([, v]) => v).filter((v) => v !== null))
  if (found.size > 1) problems.push(`versions differ: ${versions.map(([file, v]) => `${file} ${v}`).join(', ')}`)
  const [version] = found
  if (ref.startsWith('refs/tags/') && found.size === 1 && ref !== `refs/tags/v${version}`) {
    problems.push(`${ref.slice('refs/tags/'.length)} does not match the version, ${version}`)
  }
  return problems
}

/* c8 ignore start: the command line around check(), run by CI */
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = new URL('../', import.meta.url)
  const contents = Object.fromEntries(VERSION_FILES.map((file) => [file, readFileSync(new URL(file, root), 'utf8')]))
  const problems = check(contents, process.env.GITHUB_REF)
  for (const problem of problems) console.error(`✗ ${problem}`)
  if (problems.length > 0) process.exit(1)
  console.log('✓ versions agree')
}
/* c8 ignore stop */
