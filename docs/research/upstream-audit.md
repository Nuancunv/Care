# 上游仓库深度源码审计报告（`dsh-Go` & `DS-Bot`）

> **审计日期**：2026-11-25  
> **审计基线**：`ccch1mneyyy/dsh-Go@main`（v1.3.0 / DSH `0.2.2-rc.1`）、`Fei-Craft/DS-Bot@main`（v0.3.10）  
> **目标基线**：全量离线一体 `arm64-v8a` Android APK（ADR-003）、AGPL-3.0 开源改造（ADR-001）、首版去语音（ADR-002）、真机基线 OPPO Find X8s+（ColorOS）

---

## 1. `ccch1mneyyy/dsh-Go`（Android 宿主 + PRoot 引擎）审计

### 1.1 关键工程参数（源自 `app/pubspec.yaml`、`app/android/app/build.gradle.kts`、`runtime/build-runtime.sh`）
- **Dart / Flutter**：Dart SDK `^3.13.4`（Flutter 3.47+），Riverpod `^3.4.3`（手写 Notifier，无 codegen）。
- **Android 编译配置**：
  - `minSdk = 26`、`targetSdk = 28`（仿 Termux 规避 Android 10+ 私有目录 W^X `exec` 限制，保障 PRoot/Node 可执行）
  - `JavaVersion.VERSION_17` / `JvmTarget.JVM_17`
  - V1 + V2 + V3 全签名方案（适配国产 ROM 如 ColorOS 安装器）
  - 原生 `arm64` flavor 直接打包 `runtime/out/arm64-v8a/{assets,jniLibs}`，**原生支持 ADR-003 的全量离线一体 APK 架构**！
  - `noCompress += ["gz", "xz", "zst", "tar"]` + `useLegacyPackaging = true`（确保 `libproot.so`/`libproot-loader.so`/`libtalloc.so`/`libandroid-shmem.so` 释放至 `nativeLibraryDir` 可执行）。
- **内置运行时版本（`runtime/build-runtime.sh`）**：
  - DSH `0.2.2-rc.1`、Node.js `24.22.1`（arm64）、Ubuntu Base `24.04.5`（arm64）、PRoot `5.1.107.102`、`libtalloc 2.5.0`、`libandroid-shmem 0.7`、`xz -6` 压缩。
  - 已内置清华 TUNA 镜像与 npmmirror 镜像及全部 `sha256` 校验锁。

### 1.2 意外发现的高价值现成模块（可直接复用改造）
在 `app/android/.../dsh_app/` 中已具备极其完善的 Android 原生个人管家基建：
- `runtime/`：PRoot 生命周期 `RuntimeController`
- `phone/`：无障碍 / Shizuku（`dev.rikka.shizuku`）/ self-ADB（`libadb-android`）手机操控 + 原生 `SafetyGate`
- `companion/`：**已有 `CompanionReminderAndroid/Job/Receiver/Runner`（后台定时提醒调度）、`NoticeListener/NoticeInbox`（系统通知收件箱）、`CompanionWidget`（桌面小组件）**！这极大加速了 M2 主动关怀与早晚简报落地。
- `notify/`、`files/`、`nativefiles/`、`theme/`、`usage/`

### 1.3 裁剪清单（瘦身 + 去云中转 + 去首版语音）
| 模块 / 依赖 | 处置方式 | 收益 / 理由 |
| :--- | :--- | :--- |
| `sherpa_onnx`、`sherpa_onnx_android_*`、`onnxruntime-android:1.27.0`、`lib/speech`、`lib/voice`、`voice/`、`speech/` | **M1 首版移除**（遵循 ADR-002） | 释放约 35+ MB 原生 `.so` 体积，免去麦克风权限；后续按需走 DeepSeek 原生语音 API |
| `flutter_webrtc`、`packages/dsh_remote`、`packages/dartssh2`、`lib/remote` | **移除**（遵循零云中转红线） | 释放 `libwebrtc.so`（~20 MB）及远程隧道攻击面，聚焦 100% 本机直连 |
| `packages/dsh_tavern`、`lib/forum`、`lib/share_hosted`、`lib/share_code`、`lib/workshop`、`mobile_scanner`、`assets/pets/*`、`assets/tavern/*` | **移除** | 去除社区/酒馆/云分享/重型宠物动画，聚焦个人管家 Care 极简体验 |
| `com.google.mlkit:text-recognition-chinese` | **M1 暂移除** | 减重 ~15 MB；文档/图片识别可按需走 `DS-Bot` 内置的 DeepSeek `/v1/tools/ocr` |
| `app/ios/`、`app/ohos/`、`runtime/ios/`、`runtime/ohos/`、`x64` flavor | **裁剪** | 聚焦 Android `arm64-v8a` 单一目标，降低维护成本 |

---

## 2. `Fei-Craft/DS-Bot`（`plugins/care-bot` 核心大脑）审计

### 2.1 模块化架构优势
`ds-bot/index.js` 采用极其清晰的扁平插件数组 `MODULES = [...]`，每个子系统通过 `module.install(rt)` 注册工具、监听器和 HTTP 端点（`/api/bot`），**天然支持外科手术式裁剪**！

### 2.2 关键高价值模块（全部保留并改造为 `plugins/care-bot`）
- **核心编排**：`store.js`、`roster.js`、`agents.js`、`prompt.js`、`time-context.js`、`tools.js`、`turns.js`、`steer.js`、`groups.js`、`goals.js`、`tasks.js`、`approvals.js`、`channel.js`、`feed.js`、`usage.js`。
- **透明活态记忆（`memory.js` + `memory-*.js`）**：
  - 原生采用纯 Markdown（Agent Memory Repo 格式：`MEMORY.md` + `[[topic]]` 文件），支持 `bots/`、`groups/`、`team/` 分域隔离与隐私 Bot 独立 `journal.jsonl`；
  - 内置 `looksSecret` 密钥防泄露拦截与**会话级内存前缀冻结（最大化命中 DeepSeek API Context Caching 降本）**；
  - 内置对话后自动 `memory-review.js` 提炼与可视化编辑接口！
- **定时调度（`schedules.js`）**：原生对接 DSH `schedule` 服务（支持 `at`/`daily`/`weekly`/`every`/`cron` 及暂停/恢复），M2 仅需与 Kotlin `CompanionReminder` / `WorkManager` 桥接即可实现低功耗按需唤醒。
- **DeepSeek 官方服务桥（`deepseek-services.js`）**：已完整实现基于用户自有 `DEEPSEEK_API_KEY` 直连 `https://api.deepseek.com/v1/tools/{ocr,asr,tts}`，且内置严格防泄漏校验（若 `baseURL` 指向非官方域名则拒绝外发官方 Key）。**首版关闭 ASR/TTS（ADR-002），保留架构供后续一键启用！**
- **连接器与隐私**：`privacy.js`、`secrets.js`、`connectors/mail/*`（IMAP/SMTP）、`mcp-server.js`、`web-search.js`（纯 HTTP 无 Key 兜底 + Key 路由搜索）。

### 2.3 必须裁剪/禁用的桌面及云中转模块
| 模块 / 依赖 | 处置方式 | 原因 |
| :--- | :--- | :--- |
| `src/host/phone.js`（含默认 `wss://relay.dsbot.app`） & `remote.js` & `mobile.js` | **彻底移除** | 桌面端通过中继连手机的云中转模块，违反 Care 零云中转红线且本机直连无需中继 |
| `src/host/browser.js`、`src/host/browser/*`、`browser-plugins.js` 及 `playwright-core` 依赖 | **彻底移除** | ARM64 PRoot 下无法运行重型桌面浏览器且包体/内存爆炸 |
| `src/host/computer/*`（桌面键鼠操控） | **彻底移除** | 桌面专属；手机端操控由 `dsh-Go` 原生 `phone/` + `SafetyGate` 承担 |
| `src/host/local-agents/*`（Claude Code / Codex / Cursor CLI 等） | **M1 移除** | 桌面编程 CLI 适配器，移动端不适用 |
| `src/host/update.js`、`dsh-update.js`、`issue-report.js` | **移除或本地化** | 避免向外部 GitHub/上报服务发起未授权网络请求 |

---

## 3. 本机 Windows 全栈开发环境就绪评估（M0-3）

| 工具 / 组件 | 当前状态 | 所需目标 | 补齐方式 |
| :--- | :--- | :--- | :--- |
| **Node.js / npm** | ✅ `v24.15.0` / `11.12.1` | Node 24.x | 已就绪，可直接开发与测试 `plugins/care-bot` |
| **Android CLI** | ✅ `v1.1.16919734` | `android` CLI | 已安装于本地 `%LOCALAPPDATA%\AndroidCLI` |
| **Git / Git Bash** | ✅ 已安装 | Git + Bash | 已就绪 |
| **JDK** | ⚠️ 当前为 `jdk-24` | **JDK 17**（`build.gradle.kts` 硬性要求） | 可通过 `winget install Microsoft.OpenJDK.17` 安装 |
| **Android SDK** | ⚠️ 尚未安装具体包 | `platform-tools`、`platforms/android-35`、`build-tools`、`ndk` | 可直接通过 `android sdk install ...` 一键安装 |
| **Flutter SDK** | ❌ 未安装 | **Flutter 3.47+（Dart `^3.13.4`）** | 需下载安装并加入 `PATH` |
| **Linux 运行时构建环境** | ⚠️ WSL 尚未安装发行版 | 运行 `runtime/build-runtime.sh`（需 `bash`/`python3`/`xz`/`tar`） | 可选用 WSL Ubuntu、Git Bash 补齐工具，或使用 CI Linux Runner 构建 `runtime/out/arm64-v8a` |
| **真机测试** | ✅ 用户提供 **OPPO Find X8s+** | `arm64-v8a` / ColorOS | 后续通过 USB 调试（`adb` / `android install`）直接实测 |
