# ADR-001：采用 AGPL-3.0 开源路线，基于 `dsh-Go` 深度改造

- **状态**：已确认（Accepted）
- **决策日期**：2026-11-25
- **相关模块**：全局仓库、`app/`、`runtime/`、`plugins/care-bot/`

## 背景

Care 需要完整的 Android 免 Root 本机 PRoot Ubuntu/Node 运行时、Flutter 流式聊天底座、无障碍/Shizuku 手机操控与原生 `SafetyGate` 能力。上游仓库 `ccch1mneyyy/dsh-Go`（AGPL-3.0）已完整实现该基建，`Fei-Craft/DS-Bot`（Apache-2.0）则提供成熟的 Chief 主管家、多 Bot 协同与持久化记忆插件。

## 决策

1. **直接基于 `dsh-Go` 源码深度改造**，而非 Clean-Room 重写 Android 宿主层。
2. **Care 项目整体采用 AGPL-3.0 协议开源**。Apache-2.0（`DS-Bot`）与 AGPL-3.0 单向兼容，合并分发合法。
3. **合规强制要求**：
   - 保留 `dsh-Go` 的 `LICENSE`、`THIRD_PARTY_NOTICES.md` 与原始版权声明；
   - 保留 `DS-Bot` 的 `LICENSE` 与 `NOTICE` 文件；
   - 在 Care 顶层及改造模块中清晰标注上游来源与变更说明。

## 影响

- **正面**：节省约 3–4 个月底层 PRoot、Bridge 与手机操控开发工作量，聚焦个人管家产品化与零云中转改造。
- **约束**：所有衍生代码必须以 AGPL-3.0 公开源代码，严禁闭源分发。
