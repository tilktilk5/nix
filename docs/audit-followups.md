# Audit follow-ups — remaining work

Context: a security/performance/bugs/features audit of this repo (2026-07-22) shipped
the whole **Security** and **Performance** tracks plus the highest-value app bugs. This
doc captures what was *not* done yet, so it isn't lost. The items below are ordered by
value; most are UI or UI-behaviour changes that need in-the-loop visual/interaction
verification (per the `no-visual-checks` rule), which is why they were deferred rather
than shipped blind.

## Already shipped (for reference — do NOT redo)

- **Security:** `rebuild-top` sudo wrapper (no more arbitrary-flake→root); surfer
  `gmxhr://`/`surfercmd://` scheme allow-lists; slskd loopback bind + key CIDR; dropped
  inbound TCP 38899.
- **Performance:** CUDA/AI caches moved from `trusted-substituters` to `substituters`
  (they were never actually consulted); `boot.tmp.cleanOnBoot` + `fstrim` + `zramSwap` +
  journald 500M cap; pruned `vmware.host`, `labwc`, `noctalia-shell`.
- **App bugs:** filer paste/rename overwrite-confirm (was silent data loss); wal-repo-sync
  phantom-deletions + push-wedge; viewer EXIF orientation + animated GIF/WebP; viewer
  natural sort.

## Bugs / correctness

### C4. filer — blocking directory IO on the GUI thread *(medium)*
`FileOps.listDir`/`completePath`/`refreshDirSize` (`filer/main.py:365-427`) are synchronous
`os.scandir`+`stat` on the main thread (called from `Main.qml` `buildRows`/`rebuild`/
`refreshDirSize`) — a large or stalled/removable mount freezes the window (and the hyprvtb
bar). `refreshDirSize` also re-scandirs a dir `rebuild` just scanned. Move `listDir` onto
the existing `QThreadPool` (mirror `ThumbResponse`), return results via a signal; compute
`dirBytes` from the entries `rebuild` already fetched. **Needs interactive testing** — it
changes the QML data-flow (sync slot → async signal).

### C5c. hyprvtb — newline in a launch arg corrupts one session record *(low)*
`home/prog/hyprvtb/main.cpp:173` writes the cmd as the rest-of-line of a TSV; an argv token
containing `\n` splits the record. Restore is already defensively guarded (drops the entry,
no crash), so severity is low. Reject/escape embedded newlines when building `cmd`. Requires
the plugin recompile + resolved-store-path live-reload dance (see `AGENTS.md`).

### C5d. filer — duplicate concurrent thumbnail decode *(low)*
`filer/main.py:167-189` — two visible tiles for the same uncached image decode it twice
(cache never corrupts; `os.replace` is atomic). Add an in-flight `dict[thumbhash]→Future`/
lock so duplicates share one decode. Low value; be careful not to destabilise the working
thumbnail pool.

## Portability

### C7. Hardcoded `/home/lam` in Nix *(low)*
`home/prog/filer.nix:30,50`, `viewer.nix:22,38`, `surfer.nix:28,44`, `zsh.nix`,
`home/srvs/vista-sounds.nix:13`, `hypr-files/hyprland.lua:114`. Works today only because both
hosts are user `lam`. Replace with `${config.home.homeDirectory}` / `config.home.username`
and `mkOutOfStoreSymlink`. The seed-once `hyprland.lua` plugin path is the touchiest — change
it last and update the live file too. Nothing is broken today, hence low priority.

## Features (cheap, reuse existing infra)

- **viewer** titlebar buttons the bridge already supports: rotate / copy-path / trash
  (`gio trash`) / set-as-wallpaper; EXIF+dimensions in the titlebar footer.
- **filer:** client-side search/filter via the existing address-bar round-trip; one-slot
  undo for the last trash/rename/move (`gio trash --restore` + inverse `mv`); "open terminal
  here" (`kitty --directory`); bulk pattern-rename over the existing multi-select. Also wire
  the already-defined-but-dead `delDlg` (permanent delete, `Main.qml`) into a context menu.
- **panel:** random-wallpaper bind (`wal-set.sh "$(shuf -n1 …)"`); power-profile toggle
  (`powerprofilesctl`) next to the battery stat (mainly `air`).

## Desktop polish (Track D)

The DE is already very complete (native notifications, tray, launcher, screenshot flow,
power menu, hover calendar/clock/weather, wal-theming of Qt/kitty/titlebars, VU meter). The
specific gaps, each reusing existing plumbing:

1. **D1 — Clipboard picker UI *(best ratio)*.** `hyprland.lua:93-94` already runs
   `wl-paste … cliphist store`, so history is captured — there's no picker/keybind
   (`:92` says "picker UI is future work"). Add a Quickshell popup (mirror `Launcher.qml`'s
   fuzzy-list slide-in) over `cliphist list`, select → `cliphist decode | wl-copy`; bind
   `Super+V`.
2. **D2 — MPRIS now-playing widget + track-change OSD.** `playerctl` is already the
   media-key backend; add a compact title/artist/play-pause widget by the VU meter
   (Quickshell `Mpris` service, no new dep) and a `kind:"media"` reuse of `OsdWindow.qml`.
3. **D3 — Quick-settings popup.** Native audio-sink switcher (`wpctl`), wifi/BT toggles,
   power-profile toggle, and a **DND toggle** (a `dnd` bool on the `Notifications` singleton
   suppressing non-critical toasts) — removes reliance on the external `nm-applet` tray icon.
4. **D4 — Lock-screen richness.** `Lock.qml` is a clock over solid black; add the current
   wallpaper + blur/dim (and optionally D2's now-playing).
5. **D5 — GTK/Kvantum wal templates.** `wal-set.sh` recolours Quickshell/kitty/titlebars/Qt
   but not GTK/Kvantum, so GTK apps (Firefox chrome, GTK dialogs) don't follow the wallpaper.
   Add `gtk.css` + a Kvantum template in the same step-7 block.
6. **D6 — Low-battery alert.** Sound framework (`Sounds.qml`) + battery telemetry
   (`SysInfo.qml`/`StatusPanel.qml`) both exist, but low battery is display-colour-only. Wire
   a latched Vista ding + `notify-send` at a threshold. Mainly `air`.
7. **D7 — Notification history / centre.** `Notifications.qml` renders only live toasts; add
   a small history store + a "clear all" popup.

**Intentional non-goals** (consistent with existing design): window/workspace overview
(deliberately single-workspace), screen-recording, mic-mute/caps-lock OSDs.
