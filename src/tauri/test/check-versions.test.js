// Copyright 2026 Contextual, Inc. https://agentrq.com
// This notice may not be modified or removed.
// SPDX-License-Identifier: AGPL-3.0-only

import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

import { VERSION_FILES, cargoVersion, check, versionOf } from '../scripts/check-versions.mjs'

const files = (version, overrides = {}) => ({
  'package.json': JSON.stringify({ version }),
  'src-tauri/tauri.conf.json': JSON.stringify({ version }),
  'src-tauri/Cargo.toml': `[package]\nname = "a"\nversion = "${version}"\n`,
  'core/Cargo.toml': `[package]\nversion = "${version}"\n`,
  ...overrides,
})

describe('check-versions', () => {
  it('passes the files in this checkout', () => {
    const contents = Object.fromEntries(VERSION_FILES.map((file) => [file, readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')]))
    expect(check(contents)).toEqual([])
  })

  it('reads only the [package] table of a Cargo.toml', () => {
    expect(cargoVersion('[dependencies]\nversion = "9.9.9"\n[package]\nversion = "1.2.3"\n')).toBe('1.2.3')
    expect(cargoVersion('[dependencies]\nversion = "9.9.9"\n')).toBeNull()
  })

  it('reads no version from bad or empty JSON', () => {
    expect(versionOf('package.json', '{')).toBeNull()
    expect(versionOf('package.json', '{"version": ""}')).toBeNull()
  })

  it('names a file with no version, and versions that differ', () => {
    expect(check(files('1.0.0', { 'core/Cargo.toml': '' }))).toEqual(['core/Cargo.toml has no version'])
    expect(check(files('1.0.0', { 'package.json': '{"version": "1.0.1"}' }))).toEqual([
      'versions differ: package.json 1.0.1, src-tauri/tauri.conf.json 1.0.0, src-tauri/Cargo.toml 1.0.0, core/Cargo.toml 1.0.0',
    ])
  })

  it('holds a release tag to the version, and ignores a branch', () => {
    expect(check(files('1.0.0'), 'refs/tags/v1.0.0')).toEqual([])
    expect(check(files('1.0.0'), 'refs/tags/v1.0.1')).toEqual(['v1.0.1 does not match the version, 1.0.0'])
    expect(check(files('1.0.0'), 'refs/heads/main')).toEqual([])
    expect(check({}, undefined)).toHaveLength(4)
  })
})
