---
kind: meta
audience: public
cadence: living
updated: 2026-09-30
---
# claude-switchboard — router

Public kit, owner **cwi**, remote `aniket328/claude-switchboard`. Tooling only; no data, safe on any machine.

| Path | What |
|---|---|
| `cca.zsh` | `cca` — per-terminal Claude login (CLAUDE_CONFIG_DIR profiles under `$CCA_ROOT`) |
| `ccm.zsh` | `ccm` — global claude-mem observer account, status, patch/apply/restart |
| `claude-mem-account-patch.py` | per-account quota state for claude-mem's compiled worker |
| `install.sh` | adds the `source` line to ~/.zshrc |

Studio machines set `CCA_ROOT` to their own profile root before sourcing `cca.zsh`.
