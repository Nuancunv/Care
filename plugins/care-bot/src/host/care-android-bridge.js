// Care Android Loopback Bridge (M2 — Proactive & Local Ecosystem).
// Exposes Care-specific team tools that communicate strictly over 127.0.0.1 loopback
// with the Android host (zero remote cloud relay — AGENTS.md §1.1).
import { defineTool } from '@deepseek-ai/dsh-tools'
import { output } from './tools.js'

export function isLoopbackBridgeUrl(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') return false
  try {
    const parsed = new URL(raw.trim())
    return (parsed.protocol === 'http:' || parsed.protocol === 'https:') &&
      (parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost')
  } catch {
    return false
  }
}

export function install(rt) {
  const bridgeUrl = () => {
    const candidate = rt.config?.androidBridgeUrl ?? process.env.CARE_ANDROID_BRIDGE_URL
    return isLoopbackBridgeUrl(candidate) ? candidate.replace(/\/+$/, '') : undefined
  }

  async function invokeBridge(path, payload, signal) {
    const base = bridgeUrl()
    if (base === undefined) {
      return { ok: false, reason: 'Android local bridge is not attached in this process.' }
    }
    const deadline = AbortSignal.timeout(8_000)
    const combined = signal ? AbortSignal.any([signal, deadline]) : deadline
    const resp = await fetch(`${base}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload ?? {}),
      signal: combined,
      redirect: 'error',
    })
    if (!resp.ok) return { ok: false, reason: `Android bridge returned HTTP ${resp.status}` }
    return resp.json()
  }

  const careCalendarRead = defineTool({
    name: 'care_read_calendar',
    description: 'Read upcoming events from the user\'s on-device Android system calendar (requires user permission; returns empty if denied).',
    parameters: {
      days_ahead: { type: 'number', description: 'Number of days ahead to query (1 to 30, default 7)' },
    },
    output,
    async execute(args, exec) {
      const days = Math.min(30, Math.max(1, Number(args?.days_ahead ?? 7) || 7))
      const now = Date.now()
      const res = await invokeBridge('/calendar/read', { startMs: now, endMs: now + days * 86_400_000 }, exec.signal)
      return JSON.stringify(res)
    },
  })

  const careReminderCreate = defineTool({
    name: 'care_create_reminder',
    description: 'Schedule a local low-power Android notification reminder (one-shot or repeating every N days, e.g. restocking supplies).',
    parameters: {
      title: { type: 'string', description: 'Short reminder title' },
      body: { type: 'string', description: 'Helpful reminder details' },
      trigger_at_iso: { type: 'string', description: 'ISO-8601 timestamp when the reminder should fire' },
      repeat_days: { type: 'number', description: 'Optional repeat interval in days (0 = one-shot)' },
    },
    output,
    async execute(args, exec) {
      const title = String(args?.title ?? '').trim()
      if (!title) return JSON.stringify({ ok: false, reason: 'title is required' })
      const triggerMs = Date.parse(String(args?.trigger_at_iso ?? ''))
      if (Number.isNaN(triggerMs)) return JSON.stringify({ ok: false, reason: 'valid trigger_at_iso is required' })
      const repeatDays = Math.max(0, Math.floor(Number(args?.repeat_days ?? 0) || 0))
      const res = await invokeBridge(
        '/proactive/reminder',
        { title, body: String(args?.body ?? ''), triggerAtMs: triggerMs, repeatDays },
        exec.signal,
      )
      return JSON.stringify(res)
    },
  })

  const carePhoneInspect = defineTool({
    name: 'care_phone_inspect',
    description: 'Read a sanitized summary of interactive UI nodes on the user\'s current Android screen (password fields and protected system/payment apps are automatically masked or blocked).',
    parameters: {
      max_nodes: { type: 'number', description: 'Maximum UI nodes to return (default 40, max 100)' },
    },
    output,
    async execute(args, exec) {
      const maxNodes = Math.min(100, Math.max(1, Number(args?.max_nodes ?? 40) || 40))
      const res = await invokeBridge('/automation/inspect', { maxNodes }, exec.signal)
      return JSON.stringify(res)
    },
  })

  const carePhoneAction = defineTool({
    name: 'care_phone_action',
    description: 'Request an Android UI automation step (click, input text, back, home). ALWAYS gated by Android native SafetyGate approval — never executes silently.',
    parameters: {
      action: { type: 'string', enum: ['accessibility_click', 'accessibility_write', 'accessibility_back', 'accessibility_home'], description: 'Automation action type' },
      summary: { type: 'string', description: 'Clear plain-language intent shown on the user\'s native SafetyGate approval card' },
      node_text: { type: 'string', description: 'Optional visible text of target UI element' },
      text: { type: 'string', description: 'Optional text to input for accessibility_write' },
    },
    output,
    async execute(args, exec) {
      const action = String(args?.action ?? '').trim()
      const summary = String(args?.summary ?? '').trim()
      if (!action || !summary) {
        return JSON.stringify({ ok: false, reason: 'action and plain-language summary are required' })
      }
      const res = await invokeBridge(
        '/automation/request',
        {
          action,
          summary,
          nodeText: args?.node_text ? String(args.node_text) : undefined,
          text: args?.text ? String(args.text) : undefined,
          requiresNativeSafetyGate: true,
        },
        exec.signal,
      )
      return JSON.stringify(res)
    },
  })

  const careRoutineSave = defineTool({
    name: 'care_routine_save',
    description: 'Save a reusable multi-step personal Routine (SOP) locally on the user\'s Android device.',
    parameters: {
      name: { type: 'string', description: 'Short Routine title' },
      description: { type: 'string', description: 'What this Routine accomplishes' },
      steps: { type: 'array', description: 'Ordered step descriptions or actions' },
    },
    output,
    async execute(args, exec) {
      const name = String(args?.name ?? '').trim()
      if (!name) return JSON.stringify({ ok: false, reason: 'Routine name is required' })
      const res = await invokeBridge(
        '/routines/save',
        {
          name,
          description: String(args?.description ?? ''),
          steps: Array.isArray(args?.steps) ? args.steps : [],
        },
        exec.signal,
      )
      return JSON.stringify(res)
    },
  })

  rt.teamTools.push(
    careCalendarRead,
    careReminderCreate,
    carePhoneInspect,
    carePhoneAction,
    careRoutineSave,
  )

  // Expose next active DSH schedule timestamp so Kotlin WorkManager can wake briefly when due.
  rt.nextScheduledWakeAt = async () => {
    const view = await rt.schedulesEndpoint?.('schedules')
    const tasks = Array.isArray(view?.tasks) ? view.tasks : []
    let earliest = null
    for (const task of tasks) {
      if (task?.status !== 'active') continue
      const ts = Date.parse(String(task.scheduledAt ?? ''))
      if (!Number.isNaN(ts) && (earliest === null || ts < earliest)) earliest = ts
    }
    return earliest
  }

  Object.assign(rt, { isAndroidBridgeLoopback: isLoopbackBridgeUrl })
}
