// Care Mobile Local-First Stubs
// Replaces desktop-only and cloud-relay modules pruned from upstream Fei-Craft/DS-Bot:
// - phone.js / remote.js / mobile.js (zero cloud relay — ADR & AGENTS.md §1.1)
// - browser.js / browser-plugins.js / playwright-core (removed for ARM64 PRoot)
// - computer/* (desktop GUI control — Android phone control lives in Kotlin SafetyGate)
// - local-agents/* (desktop CLI coding agents)
// - update.js / dsh-update.js / issue-report.js (no unsolicited outbound telemetry/updates)

const refused = message => Object.assign(new Error(message), { code: 'bot/refused' })

// Legacy store.js migration compatibility constants (no local desktop CLI routes in Care).
export const AMBIGUOUS_OLD_ROUTES = new Set()
export const legacyRoute = () => undefined

// Disabled issue-publish action identifier kept only for channel.js view-dispatch shape.
export const PUBLISH_ISSUE = 'publish_ds_bot_issue'

export function install(rt) {
  Object.assign(rt, {
    // Desktop Playwright browser automation is permanently disabled on Android mobile runtime.
    browserEnabled: false,
    browserChannel: undefined,
    browserOpen: () => ({}),
    browserEndpoint: async () => {
      throw refused('Desktop browser automation is disabled in Care mobile runtime.')
    },

    // Desktop mouse/keyboard computer-use is disabled; Android automation goes through native SafetyGate.
    computerView: () => ({ enabled: false, reason: 'Care uses native Android SafetyGate for device actions.' }),
    computerEndpoint: async () => {
      throw refused('Desktop computer control is disabled in Care mobile runtime.')
    },

    // Upstream cloud phone relay is strictly forbidden in Care (Local-First).
    phoneView: () => ({
      server: '',
      on: false,
      status: 'disabled',
      phones: [],
      pairing: null,
    }),
    phoneEndpoint: async () => {
      throw refused('Cloud phone relay is permanently disabled in Care local-first mode.')
    },
    phoneServe: () => {},

    // Remote desktop companion / self-update / external issue publish are disabled.
    remoteView: () => ({ enabled: false }),
    updateCheck: async () => ({ supported: false, current: '0.1.0-alpha.0', latest: null }),
    dshUpdateCheck: async () => null,
    dshUpdateStart: () => {
      throw refused('In-plugin auto-update is disabled in Care all-in-one APK.')
    },
    settleIssueReport: async () => {
      throw refused('Outbound issue publishing is disabled in Care local-first mode.')
    },
  })
}
