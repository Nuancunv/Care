# Care

**Care** 是一个运行在 Android 手机上的开源个人 AI Bot 应用。

它的核心理念很简单：**本地优先、自带 Key、没有官方云端中转**——你的对话记录、记忆、资料库和隐私空间全部留在自己的手机里，模型请求直接连接你配置的 DeepSeek 官方接口（或兼容 OpenAI 协议的端点）。

## 主要功能

- **多 Bot 首页与团队协作**
  - 一级首页固定展示主 Bot（`Care Bot`），下方管理你创建的各类专职 Bot（如 `Study`、`Finance` 等），支持自定义动态形象、独立模型（`deepseek-flash` / `deepseek-v4-pro` 及 `/v1/models` 动态拉取新模型）与思考强度（关 / 低 / 高 / 极致）。
  - 支持主 Bot 通过工具直接创建新 Bot，也支持在输入框里 `@Bot` 点名，让多个 Bot 协同回答。
- **独立工作空间与「资料库」（类似 Notebook）**
  - 每个 Bot 拥有独立的工作空间和 `资料库/` 文件夹，支持导入文本、Markdown、代码以及 `.docx` / `.pptx` / `.xlsx` 课件（离线原生解析正文），对话时自动检索资料库并引用来源回答。
  - **Notebook Studio**：可根据当前资料库一键生成离线交互式 HTML 复习闪卡、自测题或思维导图。
  - **HTML 离线渲染 & 默认应用打开**：AI 写的网页可以直接在聊天卡片里点「渲染网页」查看交互效果，也支持用系统默认应用打开各类文件。
- **隐藏式 `Privacy Bot`（物理隔离）**
  - 默认在首页完全隐藏，在首页列表底部继续向上拉过阈值（或搜索 `privacy`）即可通过手机指纹/面容解锁进入暗夜隐私模式。
  - 独立目录隔离存储、切后台自动上锁清空内存，绝不与其他 Bot 共享记忆。
- **全局系统分享 & 多模态输入**
  - 在浏览器、微信、文件管理器等任意 App 里点击「分享 → Care」，可以一键选目标 Bot「存入资料库」或「直接发给它聊」。
  - 输入栏支持「选择文件 / 拍照 / 照片」多模态发送，思考过程默认折叠，不强制滚底刷屏。
- **本机提醒、定时任务与安全门**
  - 支持对话按需创建本地提醒和定时任务，默认不开启任何会自动消耗 API 额度的后台简报。
  - 涉及删除文件、跨应用无障碍操作、隐私导出等敏感动作，一律强制经过 Android 原生 `SafetyGate` 弹窗确认。

## 本地构建

环境要求：Flutter 3.47+、JDK 17、Android SDK（API 35/36）。

```bash
cd app
flutter pub get
flutter test
flutter build apk --release --flavor arm64 --target-platform android-arm64
```

也可以直接运行 Windows 打包脚本 [`scripts/build-apk.ps1`](./scripts/build-apk.ps1)。

## 目录说明

- `app/` — Flutter 客户端与 Android Kotlin 原生模块（工作空间、Office 文本解析、系统分享、生物识别加密、无障碍与安全门）
- `packages/dsh_client/` — 上游 DSH 客户端协议包
- `plugins/care-bot/` — 基于 DS-Bot 裁剪的移动适配插件（含单元测试）
- `runtime/` — 可选的离线 PRoot 运行时构建脚本与补丁
- `config/templates/` — `SOUL.md`、`MEMORY.md` 与示例配置模板
- `docs/` — 架构决策记录（ADR）与真机验收清单

## 开源协议与致谢

本项目沿用上游协议，以 **GNU Affero General Public License v3.0 (AGPL-3.0)** 开源，详见 [LICENSE](./LICENSE) 与 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

特别感谢以下开源项目带来的架构灵感与代码基础：
- [`ccch1mneyyy/dsh-Go`](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）
- [`Fei-Craft/DS-Bot`](https://github.com/Fei-Craft/DS-Bot)（Apache-2.0）
