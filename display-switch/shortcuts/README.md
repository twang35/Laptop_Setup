# shortcuts

The two Shortcuts actually in use, extracted from the live Shortcuts store
(`~/Library/Shortcuts/Shortcuts.sqlite`, `ZSHORTCUTACTIONS.ZDATA`, a binary plist).

**These are a faithful record, not an importable file.** Shortcuts imports only *signed* `.shortcut`
files, and signing requires being signed into iCloud. Rebuild them by hand from `../README.md` — one
action each — or sign these if iCloud is ever connected.

| shortcut | key | workflow id |
|---|---|---|
| Monitor to Desktop Input | **⌘⌥⌃H** | `8C7AC0FD-B3DC-4440-8A90-AF023E232F4D` |
| Monitor to Laptop Input | **⌘⌥⌃D** | `D8036A4E-E1AA-439D-A42C-C08DE1513DB3` |

H for HDMI, D for DisplayPort — named after the input, not the machine.

The key bindings are **not** in the Shortcuts store. A Shortcut with a hotkey is registered as a
macOS Service, so the binding lives in `~/Library/Preferences/pbs.plist` under
`NSServicesStatus`, keyed by `(null) - <workflow id> - runShortcutAsService` with a
`key_equivalent` in the old Services notation (`@` command, `~` option, `^` control).

Two details of the real actions worth knowing if you rebuild them:

- There is **no `Shell` parameter**. The action carries only `Script` and a `UUID`, so it runs under
  whatever Shortcuts defaults to. It does not matter: the script is invoked as a quoted path and has
  its own `#!/bin/zsh`, so the calling shell never interprets it.
- The `UUID` in each action and the workflow ids above are per-install identifiers. They will differ
  on a rebuild, and nothing depends on them except the `pbs.plist` binding.
