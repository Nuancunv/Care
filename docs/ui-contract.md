# Care UI 前端对接契约（Frontend UI Agent Handoff Contract）

> **用途**：本项目 M1 阶段已将 Flutter UI 布局留空（见 [care_app_shell.dart](../app/lib/ui/care_app_shell.dart)），并完整建好了 Android 原生层、PRoot 本机引擎桥接、DeepSeek BYOK 直连服务与 Riverpod 3 状态层。后续负责前端 UI 的智能体只需阅读本文档与 [AGENTS.md](../AGENTS.md)，即可直接在 `app/lib/ui/` 构建完整前端界面，**无需改动底层原生代码与状态逻辑**。

---

## 1. 入口与目录约定

- **替换入口**：[app/lib/ui/care_app_shell.dart](../app/lib/ui/care_app_shell.dart) 中的 `CareAppShell`（当前为空 `Scaffold`）。
- **状态总出口**：统一导入 `import 'package:care_app/state/care_providers.dart';`
- **状态管理红线**（见 `AGENTS.md §3.1`）：
  - 全项目使用 **Riverpod 3 手写 `Notifier` / `AsyncNotifier`（禁止引入 `riverpod_generator`）**；
  - UI 层只通过 `ref.watch(...)` 读状态，通过 `ref.read(x.notifier).method()` 触发操作，严禁直接修改状态或操作密钥/本机进程。

---

## 2. 可用状态 Providers 与交互接口一览

### 2.1 BYOK 密钥与模型配置：`careSettingsProvider`
- **类型**：`AsyncValue<CareSettingsState>`
- **核心字段**：
  - `hasApiKey: bool` — 是否已保存 API Key（首启未配置时引导至 BYOK 配置页）
  - `maskedApiKey: String?` — 安全脱敏显示（如 `sk-de••••4321`），**真实明文 Key 永不暴露给 UI**
  - `baseUrl: String` — 默认 `https://api.deepseek.com/v1`（直连官方，零云中转）
  - `activeModel: String` — 默认 `deepseek-chat`，可切换 `deepseek-reasoner`
  - `availableModels: List<String>` — 连通性测试后返回的可用模型列表
  - `isVerifying: bool` / `connectionVerified: bool` / `lastError: String?`
- **操作方法（`ref.read(careSettingsProvider.notifier)`）**：
  - `saveApiKey(String rawKey)` — 校验格式并加密写入 Android Keystore
  - `clearApiKey()` — 清除已存 Key
  - `setBaseUrl(String rawUrl)` — 设置自定义 OpenAI 兼容端点（远程强制 HTTPS，仅 `127.0.0.1`/`localhost` 允许 HTTP）
  - `setActiveModel(String model)` — 切换当前推理模型
  - `verifyDirectConnection()` → `Future<bool>` — 直连 `<baseUrl>/models` 校验 Key 有效性

### 2.2 本机离线运行时：`careRuntimeProvider`
- **类型**：`CareRuntimeState`（实时镜像 Android Kotlin `CareRuntimeController`）
- **核心字段**：
  - `phase: CareRuntimePhase` — `notBundled | notInstalled | installing | installed | starting | running | stopping | error`
  - `isRunning: bool` — 本机 `127.0.0.1` DSH + `care-bot` 引擎是否已就绪
  - `installProgress: double`（`0.0`–`1.0`）— 离线一体包首启解压进度
  - `bundledVersion` / `installedVersion` / `dshVersion` / `nodeVersion` / `error` / `recentLogs`
- **操作方法（`ref.read(careRuntimeProvider.notifier)`）**：
  - `installOfflineRuntime()` — 离线解压 APK 内置 ARM64 运行时（无需联网）
  - `startEngine()` — 自动读取 Keystore 中的 Key 并通过进程环境变量内存注入启动本机引擎
  - `stopEngine()` — 停止本机引擎并释放前台服务
  - `isBatteryExempt()` / `requestBatteryExempt()` — 电池优化白名单检测与跳转（OPPO ColorOS 友好）

### 2.3 永续个人助手对话：`careChatProvider`
- **类型**：`CareChatState`
- **核心字段**：
  - `messages: List<CareChatMessage>` — 历史消息列表（每条含稳定 `id`、`role`、`content`、`reasoning`、`createdAt`）
  - `draftText: String` — 当前流式输出的增量正文
  - `draftReasoning: String` — 当前流式输出的深度思考过程（`deepseek-reasoner`）
  - `isStreaming: bool` — 是否正在回复
  - `backend: CareChatBackend` — `localEngine`（本机 DSH + `care-bot`）或 `directApi`（直连 DeepSeek API 降级通道）
  - `usage: CareTokenUsage` — 本次会话累计 `promptTokens` / `completionTokens` / `totalTokens`
  - `error: String?`
- **操作方法（`ref.read(careChatProvider.notifier)`）**：
  - `sendMessage(String text)` — 发送消息（本机引擎运行时自动走 `127.0.0.1` `care-bot`，否则自动走直连 BYOK HTTPS 并注入 `SOUL.md`/`MEMORY.md`）
  - `stopStreaming()` — 立即中止当前流式输出并保留已生成文本
  - `clearThread()` — 清空当前视图对话

### 2.4 透明人格与长期记忆：`careMemoryProvider`
- **类型**：`AsyncValue<CareMemoryState>`
- **核心字段**：
  - `soulMarkdown: String` — `SOUL.md` 纯文本 Markdown
  - `memoryMarkdown: String` — `MEMORY.md` 纯文本 Markdown
  - `lastSavedAt: DateTime?` / `isSaving: bool`
- **操作方法（`ref.read(careMemoryProvider.notifier)`）**：
  - `saveSoul(String markdown)` — 原子写入本机 `SOUL.md`
  - `saveMemory(String markdown)` — 原子写入本机 `MEMORY.md`
  - `resetDefaults()` — 重置为 Care 默认人格与记忆模板

### 2.5 原生安全门审批队列：`careSafetyProvider`
- **类型**：`CareSafetyState`
- **核心字段**：
  - `pending: List<CareSafetyRequest>`（含 `id`、`action`、`summary`、`target`、`riskLevel`、`createdAtMs`）
  - `hasPending: bool` — 为 `true` 时应弹出高优先级底部审批卡（不可静默忽略）
- **操作方法（`ref.read(careSafetyProvider.notifier)`）**：
  - `approve(String id)` / `deny(String id)` — 向 Kotlin 原生 `CareSafetyGatePlugin` 回传用户显式审批结果

### 2.6 主动服务、早晚简报与提醒（M2 新增）：`careScheduleProvider`
- **类型**：`AsyncValue<CareScheduleState>`
- **核心字段**：
  - `config: CareBriefingConfig` — `morningEnabled`、`morningTime`（默认 `08:30`）、`eveningEnabled`、`eveningTime`（默认 `21:30`）、`quietStart`（`23:00`）、`quietEnd`（`07:30`）、`idleSleepMinutes`（后台闲置自动休眠分钟数，默认 `15`）
  - `reminders: List<CareReminderItem>` / `activeReminders` — 单次与周期生活提醒（含 `repeatDays`，如每 14 天猫粮补货）
  - `latestBriefing: CareBriefingSnapshot?` — 最近一次生成的早/晚简报 Markdown
  - `isGeneratingBriefing: bool`
- **操作方法（`ref.read(careScheduleProvider.notifier)`）**：
  - `updateConfig(CareBriefingConfig)` — 持久化配置并同步更新 Android `WorkManager` 定时任务与闲时休眠策略
  - `addReminder({title, body, triggerAt, repeatDays})` / `markReminderDone(id)` / `cancelReminder(id)` / `refreshReminders()`
  - `generateBriefingNow(CareBriefingKind.morning | .evening, {notify: true})` — 汇总本机日历、待办提醒、通知摘要与 `MEMORY.md` 立即生成简报并推送交互式通知

### 2.7 本机系统日历与通知摘要（M2 新增）：`careEcosystemProvider`
- **类型**：`AsyncValue<CareEcosystemState>`
- **核心字段**：
  - `calendarReadGranted` / `calendarWriteGranted` / `upcomingEvents: List<CareCalendarEvent>`
  - `noticeAccessEnabled` / `noticeAllowList: List<String>` / `recentNotices: List<CareNoticeItem>`（原生层已自动过滤验证码/OTP，仅采集白名单 App）
- **操作方法（`ref.read(careEcosystemProvider.notifier)`）**：
  - `requestCalendarPermission()` / `refresh({daysAhead})` / `createCalendarEvent(...)`
  - `openNoticeAccessSettings()` / `setNoticeAllowList(List<String>)` / `clearNotices()`

### 2.8 个人连接器（邮箱 & MCP，M2 新增）：`careConnectorProvider`
- **类型**：`AsyncValue<CareConnectorState>`
- **核心字段**：
  - `mailAccount: CareMailAccountConfig?`（IMAP/SMTP 主机端口与 `hasPassword`；授权码仅存 Android Keystore，永不暴露给 UI）
  - `mcpServers: List<CareMcpServerConfig>`（`id`、`name`、`endpointUrl`、`enabled`；远程强制 HTTPS，本地仅放行 `127.0.0.1`）
- **操作方法（`ref.read(careConnectorProvider.notifier)`）**：
  - `saveMailAccount(...)` / `removeMailAccount()`
  - `addMcpServer({name, endpointUrl})` / `toggleMcpServer(id, enabled)` / `removeMcpServer(id)`

### 2.9 手机自动化与紧急接管（M3 新增）：`careAutomationProvider`
- **类型**：`CareAutomationState`
- **核心字段**：
  - `selfCheck: CareAutomationSelfCheck` — `accessibilityEnabled`、`accessibilityConnected`、`shizukuInstalled`、`emergencyStopped`、`manufacturer`、`ready`
  - `lastScreen: CareScreenSummary?` — 脱敏后的当前屏幕可交互节点摘要（密码框与系统安全/支付 App 在原生层硬拦截）
  - `isExecuting: bool` / `emergencyStopped: bool` / `lastOutcome: String?` / `lastError: String?`
- **操作方法（`ref.read(careAutomationProvider.notifier)`）**：
  - `refreshSelfCheck()` / `openAccessibilitySettings()` / `captureScreenSummary()`
  - `executeGatedStep(...)` — 任何 L2 写操作强制先经 `careSafetyProvider` 人工审批签发一次性原生令牌
  - `emergencyStop()` / `clearEmergencyStop()` — 一键紧急停止与用户中途接管

### 2.10 本地 Routine 例程技能（M3 新增）：`careRoutineProvider`
- **类型**：`AsyncValue<CareRoutineState>`
- **核心字段**：
  - `routines: List<CareRoutine>`（默认预置 3 个高频生活例程：晚间通知与待办整理、周期耗材核对、近 3 日日程冲突核对）
  - `runningRoutineId: String?` / `lastResult: CareRoutineRunResult?`
- **操作方法（`ref.read(careRoutineProvider.notifier)`）**：
  - `createRoutine(...)` / `toggleRoutine(id, enabled)` / `deleteRoutine(id)`
  - `runRoutine(id)` — 逐步执行；遇紧急停止立刻中断，遇 L2 高危步骤自动暂停并推送原生 `SafetyGate` 审批卡

### 2.11 多 Bot 团队与隐私保险箱（M4 新增）：`careBotsProvider`
- **类型**：`AsyncValue<CareBotsState>`
- **核心字段**：
  - `bots: List<CareBotProfile>` / `specialists` / `activeBot` / `privacyBot`
  - `privacyUnlocked: bool` / `privacyMemoryMarkdown: String`（仅生物识别/锁屏密码解锁后加载，上锁与切后台即清空）
  - `biometricStatus: CareBiometricStatus`
- **操作方法（`ref.read(careBotsProvider.notifier)`）**：
  - `spawnFromTemplate(templateId)` / `spawnSpecialist(...)` / `deleteSpecialist(botId)`
  - `selectActiveBot(botId)` — 隐私 Bot 未解锁时拒绝切换
  - `unlockPrivacyVault()` / `lockPrivacyVault()` / `savePrivacyMemory(markdown)` / `wipePrivacyVault()`
  - `requestPrivacyExport({summary, target})` — 强制经由原生 `SafetyGate`（`privacy_cross_bot_export`）人工审批

### 2.12 本地加密备份与迁移（M4 新增）：`careBackupProvider`
- **类型**：`CareBackupState`
- **核心字段**：`isBusy`、`lastEnvelope`、`lastSummary`、`lastMessage`、`lastError`
- **操作方法（`ref.read(careBackupProvider.notifier)`）**：
  - `exportEncryptedBackup(passphrase)` — 本地 AES-256-GCM 加密导出（严格排除 API Key、邮箱授权码与隐私空间）
  - `importEncryptedBackup({passphrase, envelopeJson})` — 本地解密校验并恢复 `SOUL.md`、`MEMORY.md`、简报配置、例程与专职助手
  - `exportPlainMarkdown()` — 导出纯文本 Markdown 全集

---

## 3. UI 设计与性能强制约束

1. **流式渲染性能契约（`AGENTS.md §3.1`）**：
   - 外层页面仅使用 `ref.watch(careChatProvider.select((s) => (s.isStreaming, s.error, s.backend)))`，**严禁让外层页面或抽屉因 `draftText`/`draftReasoning` 单字 delta 触发全页重建**；
   - 将消息列表 `messages` 与底部流式草稿气泡 `draftText`/`draftReasoning` 拆分为独立 `ConsumerWidget`。
2. **产品语气去极客化（`AGENTS.md §3.1`）**：
   - 主界面面向普通个人用户，严禁暴露 `PRoot`、`Cordis`、`Loopback 3080`、`ARM64 rootfs` 等术语；
   - 统一收敛至「设置 → 高级诊断」页查看 `careRuntimeProvider` 的版本、阶段与脱敏日志 `recentLogs`。
3. **首版无语音入口（ADR-002）**：
   - M1 首版**不展示麦克风/语音通话按钮**，可在输入栏右侧预留后续扩展位。
4. **验证命令**：
   - UI 改动完成后，在 `app/` 目录运行 `flutter analyze` 与 `flutter test` 确保 0 报错且既有状态单测全部通过。
