// Care Bot: Mobile Local-First Personal AI Agent Cordis plugin for DeepSeek Harness.
// Derived from Fei-Craft/DS-Bot (Apache-2.0, see LICENSE.DS-Bot & NOTICE.DS-Bot).
// Pruned for Android ARM64 PRoot: zero cloud relay, zero playwright-core, zero desktop GUI hooks.
import { join } from 'node:path'
import * as diagnostics from './src/host/diagnostics.js'
import * as store from './src/host/store.js'
import * as models from './src/host/models.js'
import * as providers from './src/host/providers.js'
import * as permissions from './src/host/permissions.js'
import * as turns from './src/host/turns.js'
import * as steer from './src/host/steer.js'
import * as handoffs from './src/host/handoffs.js'
import * as requests from './src/host/requests.js'
import * as delivery from './src/host/delivery.js'
import * as roster from './src/host/roster.js'
import * as folders from './src/host/folders.js'
import * as privacy from './src/host/privacy.js'
import * as agents from './src/host/agents.js'
import * as prompt from './src/host/prompt.js'
import * as timeContext from './src/host/time-context.js'
import * as tools from './src/host/tools.js'
import * as deepseekServices from './src/host/deepseek-services.js'
import * as chatIndex from './src/host/chat-index.js'
import * as groups from './src/host/groups.js'
import * as ledger from './src/host/ledger.js'
import * as goals from './src/host/goals.js'
import * as agentCommands from './src/host/agent-commands.js'
import * as tasks from './src/host/tasks.js'
import * as approvals from './src/host/approvals.js'
import * as resume from './src/host/resume.js'
import * as memory from './src/host/memory.js'
import * as parts from './src/host/parts.js'
import * as botTasks from './src/host/bot-tasks.js'
import * as changes from './src/host/changes.js'
import * as images from './src/host/images.js'
import * as avatarLibrary from './src/host/avatar-library.js'
import * as secrets from './src/host/secrets.js'
import * as connectors from './src/host/connectors/index.js'
import * as capabilities from './src/host/capabilities.js'
import * as learning from './src/host/learning.js'
import * as schedules from './src/host/schedules.js'
import * as usage from './src/host/usage.js'
import * as thinking from './src/host/thinking.js'
import * as feed from './src/host/feed.js'
import * as mcpServer from './src/host/mcp-server.js'
import * as im from './src/host/im/index.js'
import * as careMobileStubs from './src/host/care-mobile-stubs.js'
import * as careAndroidBridge from './src/host/care-android-bridge.js'
import * as channel from './src/host/channel.js'
import * as goalSkills from './src/host/goal-skills.js'
import * as manualSkills from './src/host/manual-skills.js'

export { COLORS } from './src/host/constants.js'
export { name, inject } from './src/host/entry.js'

// Keep registration order aligned with DS-Bot invariants:
// - privacy checks calls before tool hooks run;
// - usage meters model requests after rewrites;
// - careMobileStubs registers disabled stubs before channel.js mounts /api/bot.
const MODULES = [
  diagnostics,
  store,
  ledger,
  models,
  providers,
  permissions,
  turns,
  steer,
  handoffs,
  requests,
  delivery,
  roster,
  folders,
  privacy,
  agents,
  prompt,
  timeContext,
  tools,
  deepseekServices,
  chatIndex,
  groups,
  goals,
  agentCommands,
  tasks,
  approvals,
  resume,
  memory,
  parts,
  botTasks,
  changes,
  images,
  avatarLibrary,
  secrets,
  connectors,
  capabilities,
  learning,
  schedules,
  usage,
  thinking,
  feed,
  mcpServer,
  im,
  careMobileStubs,
  careAndroidBridge,
  channel,
  goalSkills,
  manualSkills,
]

export function apply(ctx, config = {}) {
  createRuntime(ctx, config)
}

export function createRuntime(ctx, config = {}) {
  const dshHome = folders.dshHomeOf(process.env.DSH_HOME)
  const home = config.home ?? join(dshHome, 'care-bot')
  const rt = {
    ctx,
    config,
    dshHome,
    home,
    statePath: join(home, 'state.json'),
    teamTools: [],
    installed: false,
    defaults: {
      mainName: config.mainName ?? 'Care',
      mainRole: config.mainRole ?? 'Personal AI Assistant & Chief of Staff',
    },
  }
  for (const module of MODULES) module.install(rt)
  rt.installed = true
  rt.syncScopedTools?.()
  void rt.adoptLiveWork?.().catch(error => rt.warn?.('care-bot: adopting live work failed: %s', error))
  return rt
}
