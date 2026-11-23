# Herdr

English | [简体中文](Herdr-zh-CN.md)

This page covers the Apollo layout for the terminal workspace app. The app is **Apollo.app**, a renamed copy of [Herdr](https://herdr.dev) that replaced Herdr.app. It loads Herdr's settings home, `~/.config/herdr-app`, so everything below still installs there. The layout lives in its own public repo, [herdr-config](https://github.com/MOSconfig/herdr-config). This repo includes it as a Git submodule at `config/herdr`. The submodule follows herdr-config's `main`: every install moves it to the latest commit.

The separate `herdr` terminal app (the TUI) gets the same theme; see [Herdr TUI](#herdr-tui).

## What install does

`./install.sh` (and `uu`, which runs it) does these steps on macOS. It never installs Herdr or Apollo.app; install Apollo.app by hand.

1. **Update the submodule.** It runs `git submodule update --init --remote config/herdr`, which fetches herdr-config and checks out the latest `main`. Offline with a checkout, it prints one `Herdr config: could not update` line and installs from the current checkout. It never rolls back to the older commit that dot-configs records. If herdr-config's `main` no longer has `user/settings.json` or `user/keys.json`, the checkout stays put with one line, so your live settings and keys links never dangle. Offline without a checkout, the Herdr rows are skipped with one `Herdr config:` line. Everything else installs either way.
2. **Keep your live values.** It reads the live `settings.json` and `keys.json`, and writes them into `config/herdr/user/` when they differ. If writing one back fails, the warning names the temp folder that still holds your values. If your `keys.json` is still Herdr's default, the Apollo keymap is used instead.
3. **Install the files.** Layouts, the theme, `settings.json`, `keys.json` and the agent script are links. Mods are copies; see below.
4. **Put the Dock icon back.** Re-signing or copying `Apollo.app` drops its custom icon. If `config/herdr/scripts/set-app-icon.sh --check --app <Apollo.app>` finds no custom icon, the installer sets the Apollo icon again. It looks in `~/Applications`, then `/Applications`. A failure prints a warning and goes on.

No backup of any kind is kept: no seed folder, no archive, no `.bak` file.

## Installed paths

| Source | Home destination | Type |
|---|---|---|
| `config/herdr/layouts/*` | `~/.config/herdr-app/layouts/*` | `link` |
| `config/herdr/themes/*` | `~/.config/herdr-app/themes/*` | `link` |
| `config/herdr/user/settings.json` | `~/.config/herdr-app/settings.json` | `link` |
| `config/herdr/user/keys.json` | `~/.config/herdr-app/keys.json` | `link` |
| `config/herdr/mods/**` | `~/.config/herdr-app/mods/**` | `copy` |
| `config/herdr/agent/herdr-context.sh` | `~/.local/bin/herdr-agent-context` | `link` |

## Why mods are copies

Herdr does not load a mod's `svg()` and `image()` files through a link, so its icons would be blank. Each mod file is a `copy` row instead. See [Repository operations](Repository-Operations.md) for how copies are kept in step and removed.

## Herdr TUI

The `herdr` terminal app (installed by hand, for example `brew install herdr`) reads one file, `~/.config/herdr/config.toml`. It has no include, so `./install.sh` generates the whole file from `config/herdr/themes/apollo.json`, the theme the Herdr app loads. Both apps then show the same colors, and a herdr-config theme change reaches both on the next `uu`.

The generated file lives at `~/.local/state/dot-configs/herdr/config.toml`. `~/.config/herdr/config.toml` is a link to it. The installer function is `herdr_tui_generate` in `install.sh`.

| Herdr TUI token | App theme key |
|---|---|
| `accent`, `peach` | `colors.accent` |
| `panel_bg`, `sidebar_bg` | `colors.chrome` |
| `active_row_bg`, `surface_dim` | `colors.surface` |
| `selection_bg`, `surface0` | `colors.selected` |
| `surface1` | `colors.hover` |
| `overlay0` | `colors.dim` |
| `overlay1`, `subtext0` | `colors.muted` |
| `text` | `colors.foreground` |
| `green`, `yellow`, `red` | `colors.done`, `colors.working`, `colors.blocked` |
| `blue`, `mauve`, `teal` | `ansi[4]`, `ansi[5]`, `ansi[6]` |

The layout follows Apollo tmux: tab bar at the bottom, a zoom mark and an `HH:MM` clock on the right, no outer frame or gaps between panes, and symbol status marks.

Install never replaces your own Herdr TUI config:

- It links `~/.config/herdr/config.toml` only when nothing is there. Any other file, link, or folder there is kept, with one warning. To switch, move it aside and rerun `./install.sh`.
- It never writes through a link. If a link sits below your home folder on the way to `~/.config/herdr` or `~/.local/state/dot-configs/herdr`, it warns and changes nothing.
- A missing or bad color in the theme warns and keeps the current file.

When it makes the link or the generated file changes, install runs `herdr config check` on that file, then `herdr server reload-config`. A failure only warns. If `HERDR_CONFIG_PATH` points to another file, it does not reload. An unchanged rerun does not call `herdr`.

To change the look, edit `themes/apollo.json` in herdr-config, or the token map in `herdr_tui_generate`. Edits to the generated file are lost on the next change.

## Agent hooks

Claude Code and Copilot CLI run this at session start:

```sh
[ -x ~/.local/bin/herdr-agent-context ] && ~/.local/bin/herdr-agent-context claude || true
```

(Copilot uses `copilot` in place of `claude`.) Inside a Herdr terminal it adds a short note: this is Herdr, the terminal's address, and to run `herdr-app --skill` and `hc --skill` first. Outside Herdr, in the Claude desktop app, or with the script missing, it prints nothing.

## Settings edits

`.gitmodules` sets `branch = main` and `ignore = all` for `config/herdr`. Herdr's own writes to `settings.json` and `keys.json` never block `uu`, and the moving checkout never shows up in `git status`. To keep an edit for every machine, commit it to herdr-config's `main`; the next `uu` on each machine picks it up.

## Follow main

Nothing needs bumping. The commit dot-configs records for `config/herdr` is only where a fresh clone and CI start; each install then moves to the latest `main`. CI tests that recorded commit, not `main`.

`ignore = all` in `.gitmodules` keeps `git add -A` and `git commit -a` from recording the moved commit (git 2.54+). To move the recorded commit on purpose, for example so fresh clones start nearer `main`:

```sh
git -C config/herdr fetch
git -C config/herdr checkout origin/main
git add --force config/herdr
```

`scripts/check.sh` checks that `.gitmodules` tracks `main` with `ignore = all`, that `install.sh` updates with `--remote`. It also checks that the manifest rows match the checkout's files, so a file added or removed upstream fails the check until `config/manifest.tsv` is updated.

