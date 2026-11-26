# Third-Party Notices — Care

Care is released under the **GNU Affero General Public License v3.0 (AGPL-3.0)** (see [ADR-001](docs/adr/ADR-001-open-source-agpl-fork-strategy.md)).

Care incorporates and adapts code from the following upstream open-source projects, whose original licenses, copyrights, and notices are preserved in full:

---

## 1. `ccch1mneyyy/dsh-Go`
- **Source**: https://github.com/ccch1mneyyy/dsh-Go
- **License**: GNU Affero General Public License v3.0 (`AGPL-3.0`; SDK/examples under `MIT`)
- **Usage in Care**: Android Flutter/Kotlin host architecture, PRoot Ubuntu 24.04 + Node.js local runtime packaging (`runtime/`), `dsh_client`, Android phone control (`phone/`), native `SafetyGate`, and companion reminders (`app/`).
- **Attribution**: Upstream `LICENSE` and `THIRD_PARTY_NOTICES.md` are retained verbatim upon porting modules into `app/` and `runtime/`.

## 2. `Fei-Craft/DS-Bot`
- **Source**: https://github.com/Fei-Craft/DS-Bot
- **License**: Apache License 2.0 (`Apache-2.0`)
- **Usage in Care**: Core Cordis multi-agent plugin, Chief/Care orchestration, Markdown `MEMORY.md` engine, schedules, privacy Bot isolation, DeepSeek official services bridge, and connectors — pruned and adapted for mobile ARM64 local-first execution under `plugins/care-bot/`.
- **Attribution**: Original `LICENSE` and `NOTICE` are preserved at [plugins/care-bot/LICENSE.DS-Bot](plugins/care-bot/LICENSE.DS-Bot) and [plugins/care-bot/NOTICE.DS-Bot](plugins/care-bot/NOTICE.DS-Bot).
