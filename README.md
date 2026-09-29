# claude-switchboard

**Run Claude Code under several Claude subscriptions, switch per terminal, and keep [claude-mem](https://github.com/thedotmack/claude-mem) remembering while you do.**

Two zsh commands:

| Command | Switches | Scope |
|---|---|---|
| `cca <name>` | which Claude login **this terminal's** Claude Code uses | one terminal |
| `ccm <name>` | which Claude login the **claude-mem observer** bills | the whole machine |

They are deliberately independent. You can run a work session in one tab, a personal session in another, and have claude-mem's background summariser bill a third account, and none of them moves the others.

Plus `claude-mem-account-patch.py`, a small patch to claude-mem that makes its quota pause **per account**, so switching the observer to an account with headroom resumes memory capture immediately instead of losing the queue.

---

## Who this is for

You have more than one Claude subscription on one machine, for example:

- a work seat and a personal Max plan,
- one login per client organisation, because each client pays for its own seat,
- a team plan for day-to-day work and a separate account for long background jobs.

Claude Code supports this through `CLAUDE_CONFIG_DIR`, but by hand it's fiddly. claude-mem makes it harder, because it runs **one** background worker for every session on the machine, and that worker bills **one** account.

## The problem this solves

claude-mem summarises every tool call into "observations" using a small model (Haiku) through a Claude subscription. In claude-mem 13.28:

1. The observer bills the account named in `~/.claude-mem/settings.json` → `CLAUDE_MEM_CLAUDE_CONFIG_DIR`.
2. When that account reaches **93% of its weekly limit** (or 95% of the 5-hour window), claude-mem **pauses** itself and keeps queueing observations in RAM.
3. The pause and the rate-limit readings behind it are stored **by provider / time window, not by account**. So after you point the observer at a different, healthy account, the old account's reading still blocks it, until that reading's reset date, which can be days away.
4. The queue lives **only in RAM** (by design upstream). The one stock way to clear the pause is a restart, and a restart **throws the queue away**.

We hit this on a real machine: one account at 97% weekly paused memory capture for every account for two days, with ~3,000 observations waiting, while another account sat at 19%.

With claude-switchboard:

- `ccm other-account` → the next observation runs on the new account, the old pause is ignored, and the queue drains. No restart, nothing lost.
- `cca` never touches claude-mem, so opening a terminal on a nearly-full account can't knock memory over.

## Install

Requirements: **zsh**, **python3**, [Claude Code](https://docs.claude.com/en/docs/claude-code). macOS or Linux. claude-mem is optional (`ccm` needs it; `cca` doesn't).

```bash
git clone https://github.com/aniket328/claude-switchboard ~/.local/share/claude-switchboard
~/.local/share/claude-switchboard/install.sh
exec zsh
```

The installer adds three lines to `~/.zshrc` (between `# >>> claude-switchboard >>>` markers) and creates `~/.claude-accounts/`. Set `CCA_ROOT` before installing to keep profiles somewhere else.

## `cca` — the account of this terminal

```text
cca                 list logins (* = active in this terminal)
cca <name>          this terminal now runs Claude Code as <name>
cca base            back to ~/.claude (your default login)
cca add <name>      create a profile, then `cca login <name>`
cca login [name]    browser login for that profile (about once a month)
cca status [name]   who is logged in
cca rm <name>       log out and delete the profile
```

How it works:

- Each extra login is a folder `~/.claude-accounts/<name>/` used as `CLAUDE_CONFIG_DIR`. `cca <name>` only exports that variable in the current shell.
- Settings, plugins, skills, hooks, agents, `CLAUDE.md`, transcripts and history are **symlinked** from `~/.claude`, so every profile sees the same setup. Only the login differs.
- Credentials are never copied. Each profile keeps its own keychain entry (macOS: `Claude Code-credentials-<sha256(dir)[:8]>`) or `.credentials.json` (Linux) and refreshes it itself. Copying tokens between profiles breaks them: refresh tokens are single-use.

## `ccm` — the account claude-mem bills

```text
ccm                 status: account in use, weekly/5-hour usage of every login, queue, pause, patch
ccm <name> | base   bill that login from the next observation (asks if it is above 85% weekly)
ccm auto            bill the login with the most weekly headroom
ccm patch           apply the per-account patch to the installed claude-mem
ccm apply           load the patch: waits until the queue is empty, then restarts the worker (~2 s)
ccm restart         restart now even with a queue (asks; queued observations are lost)
```

Example status:

```text
claude-mem bills: work   (ccm <name> to change; independent of cca)
    base       7d 96% · 5h 0%       —
  > work       7d 21% · 5h 11%      ok
    personal   7d 77% · 5h 28%      ok
worker: pid 64060 · up 67h · queue 12 in RAM · last spawn billed work
patch: LOADED — pauses and readings are per account; ccm <name> resumes the queue at once
```

Usage figures come from the same OAuth usage endpoint Claude Code's `/usage` screen uses, called with each profile's own token.

### First-time setup with claude-mem

```bash
ccm patch     # patches the installed claude-mem build (keeps a .orig backup)
ccm apply     # waits for an empty queue, then restarts the worker once so the patch is live
ccm           # should say: patch: LOADED
```

Re-run `ccm patch && ccm apply` **after every claude-mem update**. An update replaces the patched file, and `ccm` shows `patch: MISSING` when that has happened.

### What can still lose observations

| Event | Queue lost? |
|---|---|
| Observer paused, then resumes (or you `ccm` to another account) | No |
| `ccm apply` | No: it only restarts at queue 0. A tool call made in the ~2 s restart gap may be skipped. |
| Mac/Linux reboot, worker crash, claude-mem update, `ccm restart` | **Yes**, whatever was queued in RAM |

Your Claude Code transcripts on disk are never touched. Only the summarised memory built from them is at risk.

## The patch, precisely

`claude-mem-account-patch.py` edits claude-mem's built worker (`scripts/worker-service.cjs`) in six places:

1. every rate-limit reading is tagged with the account (the basename of `CLAUDE_MEM_CLAUDE_CONFIG_DIR`, `default` for `~/.claude`);
2. the quota guard ignores readings from other accounts;
3. a Claude cooldown ("pause") records the account that caused it;
4. admission drops a pause that belongs to a different account (including older pauses with no account);
5. and 6. the account is saved to and loaded from `quota-cooldown.json`.

It is idempotent, syntax-checks the result with `node --check` before replacing anything, keeps `worker-service.cjs.orig`, and refuses to touch a build whose code it doesn't recognise. Revert with `python3 claude-mem-account-patch.py --revert`.

Tested against claude-mem **13.28.0**. The upstream fix is proposed in claude-mem (see below). Once it ships, the patch becomes unnecessary and `ccm` keeps working without it.

## Upstream

- Issue: _link added on publish_
- Pull request: _link added on publish_
- Related upstream work: #4263 (stale readings within one account), #4068 (queue lost on restart).

## Using several subscriptions responsibly

This tool switches between logins **you own**. It does not share, pool or resell accounts, and it doesn't make any single account exceed its limits. Keep each subscription within Anthropic's terms, and keep work that belongs to one organisation on that organisation's seat. `cca` exists largely to make that separation easy.

## Limitations

- zsh only (the functions use zsh parameter expansion).
- macOS keychain and Linux `.credentials.json` are supported; Windows is not.
- The usage endpoint is undocumented and may change; `ccm` shows `unknown` rather than guessing.
- The patch targets claude-mem's compiled output, so a new claude-mem build may need new anchors. It will say so instead of half-patching.

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Built on top of [claude-mem](https://github.com/thedotmack/claude-mem) by Alex Newman (Apache-2.0).
Not affiliated with Anthropic or the claude-mem project. Made at CWI Studio.
