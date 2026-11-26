import assert from 'node:assert/strict'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { mkdtempSync, rmSync } from 'node:fs'
import test from 'node:test'
import { createRuntime } from '../index.js'
import { fakeContext } from './fake-ctx.js'

const ROOT = resolve(import.meta.dirname, '..')

function walkJs(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name)
    if (entry.isDirectory()) walkJs(full, out)
    else if (entry.name.endsWith('.js') || entry.name.endsWith('.mjs')) out.push(full)
  }
  return out
}

test('package.json contains no playwright-core or desktop browser dependencies', () => {
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'))
  const allDeps = { ...pkg.dependencies, ...pkg.devDependencies }
  assert.equal(allDeps['playwright-core'], undefined, 'playwright-core must not be in care-bot')
  assert.equal(allDeps.react, undefined, 'desktop React client must not be in care-bot host package')
})

test('upstream Apache-2.0 LICENSE and NOTICE are preserved (AGENTS.md §1.5)', () => {
  assert.ok(existsSync(join(ROOT, 'LICENSE.DS-Bot')), 'LICENSE.DS-Bot must be preserved')
  assert.ok(existsSync(join(ROOT, 'NOTICE.DS-Bot')), 'NOTICE.DS-Bot must be preserved')
})

test('source tree has zero cloud relay URLs and zero playwright imports (AGENTS.md §1.1)', () => {
  const files = [join(ROOT, 'index.js'), join(ROOT, 'plugin.js'), ...walkJs(join(ROOT, 'src'))]
  for (const file of files) {
    const text = readFileSync(file, 'utf8')
    assert.doesNotMatch(text, /relay\.dsbot\.app/i, `Forbidden cloud relay reference in ${file}`)
    assert.doesNotMatch(text, /['"]playwright-core['"]/, `Forbidden playwright-core import in ${file}`)
  }
})

test('care-bot boots cleanly in local-first mode with Care defaults and disabled relay/desktop stubs', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'care-bot-test-'))
  try {
    const ctx = fakeContext()
    const rt = createRuntime(ctx, { home: dir })
    assert.equal(rt.installed, true)
    assert.equal(rt.defaults.mainName, 'Care')
    assert.equal(rt.browserEnabled, false)
    assert.equal(rt.memoryEnabled !== false, true)
    assert.equal(rt.computerView().enabled, false)

    // Cloud phone relay must stay permanently disabled and refuse configuration.
    const phone = rt.phoneView()
    assert.equal(phone.on, false)
    assert.equal(phone.status, 'disabled')
    await assert.rejects(() => rt.phoneEndpoint('phone-set', { on: true }), /disabled/i)

    // ADR-002: DeepSeek voice TTS/OCR must default to off.
    const prefs = rt.servicePrefs()
    assert.equal(prefs.ocr, false)
    assert.notEqual(prefs.tts, 'deepseek')

    // M2 + M3: care-android-bridge tools are registered and refuse non-loopback bridge URLs.
    const toolNames = rt.teamTools.map(t => t.name)
    assert.ok(toolNames.includes('care_read_calendar'))
    assert.ok(toolNames.includes('care_create_reminder'))
    assert.ok(toolNames.includes('care_phone_inspect'))
    assert.ok(toolNames.includes('care_phone_action'))
    assert.ok(toolNames.includes('care_routine_save'))
    assert.equal(rt.isAndroidBridgeLoopback('http://127.0.0.1:43080'), true)
    assert.equal(rt.isAndroidBridgeLoopback('https://evil.example.com'), false)

    await ctx.dispose()
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
