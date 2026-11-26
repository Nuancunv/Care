# Care — 本机离线 ARM64 运行时（PRoot Ubuntu + Node + DSH + `care-bot`）

本目录移植并精简自 `ccch1mneyyy/dsh-Go/runtime/`（AGPL-3.0，参见根级 `THIRD_PARTY_NOTICES.md`），仅保留 Android `arm64-v8a` 目标，并配套 [`care-patch.yml`](./care-patch.yml) 以默认挂载 [`plugins/care-bot`](../plugins/care-bot/)。

## 构建全量离线运行时产物（ADR-003）

在 Linux / WSL Ubuntu / GitHub Actions Linux 环境下执行：

```bash
# 1. 构建基础 Ubuntu 24.04 + Node 24 + DSH 0.2.2-rc.1 + PRoot (arm64-v8a)
bash runtime/build-runtime.sh arm64-v8a

# 2. 产物将生成于 runtime/out/arm64-v8a/{assets,jniLibs}
#    app/android/app/build.gradle.kts 的 arm64 flavor 会自动将其打入全量离线一体 APK。
```

> 说明：Windows 开发机可直接运行 `scripts/build-apk.ps1` 构建并验证 Care App 与直连 BYOK 通路；待需打包全量离线 PRoot 资产时，在 WSL Ubuntu 或 CI Linux 中生成 `runtime/out/arm64-v8a/` 后重新执行 `scripts/build-apk.ps1` 即可产出完整全量离线一体 APK。
