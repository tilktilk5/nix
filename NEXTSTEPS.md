# NEXTSTEPS — sharing this config between `top` and the MacBook Air (`air`)

> Status: **fully working on air** (this machine, OS hostname `book`, Fedora Asahi
> Remix, aarch64) as of 2026-07-20. `home-manager switch -b backup --flake
> /home/lam/Downloads/git/nix#air` has run successfully. `top` untouched.
> `hyprvtb` titlebars load, scale is `1.67`, and a battery module is in the panel.
> See "Facts worth keeping" below for a dead end worth not repeating (running
> nixpkgs' own Hyprland as air's compositor) before touching `hyprvtb`/scale again.

## Decision (superseding the earlier NixOS-on-Asahi plan)

An earlier version of this doc planned full **NixOS-on-Asahi** for the MBA via the
`nixos-apple-silicon`/`apple-silicon-support` flake. That's been dropped: Fedora Asahi
Remix has meaningfully better Apple Silicon hardware/GPU support than the community
NixOS Asahi port, and installing NixOS as the OS would have required a USB installer
(which triggered this whole reconsideration — no USB-C→A adapter was on hand).

Instead: **keep Fedora, add the Nix package manager + a standalone `home-manager`
config on top.** No OS reinstall, no bootloader/ISO risk, no `hosts/air/` — `sys/*`
stays NixOS-only and simply doesn't apply to `air`.

## What changed in the repo

- `flake.nix`: overlay list deduplicated into a `mkPkgs` helper; `host = "top"` is
  threaded into `nixosConfigurations.top`'s `specialArgs`/home-manager
  `extraSpecialArgs`; a new `homeConfigurations.air` output
  (`home-manager.lib.homeManagerConfiguration`, `aarch64-linux`, same overlays,
  `host = "air"`) reuses `./lam.nix` unchanged. No dual-wiring risk — that footgun
  (documented in `flake.nix`) was about `top` having two home-manager entry points
  for the *same* machine; `air` has no NixOS layer to collide with.
- `home/prog/zsh.nix`: `update`/`rbsys`/`rbhome`/`trash` branch on `host` —
  `nixos-rebuild switch --flake ...#top` on top, `home-manager switch --flake
  ...#air` on air (no passwordless-sudo rule exists there, so `trash` drops `sudo`).
- Screen scale (Retina wants ~2, top's external monitor is 1): `home/prog/hypr-host.nix`
  (new) renders a read-only `~/.config/hypr/host.lua` from `host`;
  `home/prog/hypr-files/hyprland.lua`'s monitor block `dofile`s it with a `scale or
  "1"` fallback. `home/plasma.nix`'s `kwinrc.Xwayland.Scale` branches the same way
  for Xwayland/KDE app scaling.
- Brightness: `home/prog/quickshell-files/SysInfo.qml` now detects a real panel
  backlight at startup (`ls /sys/class/backlight/*/brightness`) and uses
  `brightnessctl` when present, falling back to the existing `ddcutil` (external
  monitor DDC/CI) path verbatim otherwise. `Osd.qml` needed no change — it already
  just reads `SysInfo.brightness` rather than querying hardware itself.
- x86_64-only packages gated with `lib.optionals pkgs.stdenv.hostPlatform.isx86_64`
  (not `host ==`, since the real constraint is architecture): `vcv-rack`, `pcsx2`,
  `vintagestory` (`home/pkgs/desktop/misc.nix`); `google-chrome`
  (`home/pkgs/desktop/net.nix`); `wineWow64Packages.staging`
  (`home/pkgs/desktop/utils.nix`); `spotify` (`home/pkgs/media/consume.nix`);
  `dwarf-fortress-packages.*` (`home/pkgs/game.nix`, whole `home.packages` list
  guarded so the attribute path itself is never forced on aarch64, since it may not
  exist there at all).
- `hyprvtb` on air (see "Facts worth keeping" below for the fix and why a plugin
  ABI mismatch happens at all): `home/prog/hyprvtb.nix` builds it against a
  `pkgs.extend`-overridden hyprland with `GIT_*` env forced to `"unknown"` for
  `host == "air"` only; `top` untouched.
- Battery module: `home/prog/quickshell-files/scripts/sysinfo.sh` now emits
  `batteryPct|batteryCharging` by scanning `/sys/class/power_supply/BAT*`
  (`-1|0` when absent); `SysInfo.qml` parses it into `batteryPct`/
  `batteryCharging`; `StatusPanel.qml` shows a `bat` stat colored by charging/low
  state. No `host` check anywhere — it's hardware-detected like brightness's
  `useBacklight` above, so it just doesn't appear on `top` (no `BAT*` node there).

## Facts worth keeping (carried over from the earlier version of this doc)

- **Rice delivery asymmetry:** `home/prog/hyprland.nix` seeds `hyprland.lua` as a
  writable copy *only if absent* (`install … || true` in
  `home.activation.seedHyprMutableFiles`); `home/prog/quickshell.nix` seeds
  `Theme.qml` the same way but ships all other `*.qml` as read-only store symlinks.
  So editing the shared `hyprland.lua` *template* does not touch `top`'s
  already-seeded live file — only a fresh seed (a first activation on `air`) picks
  up the new `host.lua`-driven scale. `SysInfo.qml`/`Osd.qml` edits, being plain
  store symlinks, propagate to both hosts immediately on switch.
- `Theme.qml` (`barWidth=48`, pixel fonts) needed no scale-specific change:
  QtWayland layer-shell surfaces honor the compositor's `wl_output` scale, so
  Hyprland `scale=2` auto-scales the panel. Worth visually confirming on `air`
  once it's live; add a per-host `barWidth` only if that proves wrong.
- `no_hardware_cursors` / trackball / touchpad blocks are harmless no-ops on the MBA.

## What actually happened getting it activated (read before repeating steps)

Bring-up on air went through several rounds — worth knowing before touching this again:

- **Nix and dnf both need an interactive sudo password.** Neither can be run
  non-interactively from an agent session; you have to run the install/dnf
  commands yourself in a real terminal.
- **Untracked new files are invisible to the flake.** Nix's git-aware flake source
  only sees `git add`-ed content. `home/prog/hypr-host.nix` silently evaluated to
  nothing (no error!) the first time because it was only `Write`d, never staged.
  **Always `git add` a new file before evaluating/building the flake against it.**
- **Disk is tight on this machine** (~62G root, was down to ~6-7G free mid-build).
  Cleared regenerable caches (`~/.cache/{mozilla,qutebrowser,drkonqi,appstream,
  falkon,mesa_shader_cache,discover}`) for headroom; `dnf clean all` /
  `journalctl --vacuum-size` need sudo too and were left undone. Keep an eye on
  `df -h /` during any future big rebuild here.
- **Several packages compile from source on aarch64 with no cache hit** and got
  gated off `air` for now (`host != "air"` / `host == "top"` in the relevant
  `home/pkgs/*.nix` file) rather than waiting through the build: `gimp`,
  `libreoffice-qt-fresh` (`desktop/utils.nix`), `fooyin` (`media/consume.nix`).
  `discord` also needed adding to the existing x86_64-only gate in
  `desktop/misc.nix` — it's not just unavailable via `lib.optionals isX86`, it was
  still listed unconditionally and broke eval on aarch64.
- **`breeze-square-overlay` forced a from-source KDE Frameworks rebuild** even
  after removing `breeze` from `home/pkgs/desktop/kde.nix`'s package list, because
  `plasma-manager` pulls `kdePackages.breeze` in transitively regardless of
  `home.packages`. Fixed at the *overlay* level instead — `flake.nix`'s `pkgsAir`
  now omits `breeze-square-overlay` entirely (`mkPkgs` takes an explicit overlay
  list per call now). Net effect: air's Breeze has round corners for now, `top`
  unaffected. Add the overlay back to `pkgsAir` if squared corners matter more
  than avoiding that rebuild.
- **A large chunk of `home/pkgs/*` overlaps what's already native on this Fedora
  install** (this machine is literally where the rice originally came from, per
  the top of this doc) — `hyprland` itself plus its ecosystem, `waybar`,
  `quickshell`, `kitty`, `firefox`, `qutebrowser`, `mpv`, `yt-dlp`, `git`, `curl`,
  and a long tail of small CLI tools. All gated `host != "air"` in their
  respective files (`base.nix`, `desktop/wm.nix`, `dev.nix`, `desktop/net.nix`,
  `media/aquire.nix`, `media/consume.nix`) rather than installed twice. If you add
  a *new* package to a shared file later, sanity-check it against `rpm -qa` on air
  before assuming it needs a fresh Nix build.
- **Standalone `home-manager switch` needs `-b backup` on the CLI**, not a config
  option — `backupFileExtension` only exists for the NixOS-module form (`top`).
  Even with `-b backup`, it still hard-refused once: two stale systemd "enabled"
  symlinks under `~/.config/systemd/user/default.target.wants/{wal-prepare,
  wal-set}.path` (leftover from a native `systemctl --user enable` before Nix
  managed them) aren't covered by the backup mechanism at all. Had to `rm` those
  two by hand before the switch would proceed — safe, they're just enablement
  markers, home-manager regenerates its own.
- **The pre-existing live `~/.config/hypr/hyprland.lua` predated `hyprvtb` and
  `quickshell` entirely** (old, never touched by the seed-once-if-absent logic).
  It's now been replaced with the current template (backup at
  `~/.config/hypr/hyprland.lua.preseed-backup`) so `host.lua`-driven scale and the
  `hyprvtb` plugin-load line are actually present. Its old hardcoded scale was
  `"1.67"`, not `"1"` or `"2"` — that's now `home/prog/hypr-host.nix`'s real value
  for `air`, not a guess.
- **A plain `hyprctl reload` is enough for most config changes** (monitor, binds,
  plugin load attempts) without logging out. It does **not** re-run the
  `hl.on("hyprland.start", ...)` autostart block (quickshell, hypridle, polkit
  agent, wal-set.sh) — that only fires once per actual Hyprland process lifetime,
  so those need a real logout/login (or Hyprland restart) to start for the first
  time after adopting the new template.

## `hyprvtb` on air — root cause, fix, and a dead end not to repeat

Root cause (confirmed, not a guess): `hyprctl plugin load` on air was failing with
`plugin crashed/threw in main: [hyprvtb] Version mismatch`. Fedora's native
Hyprland (`hyprland-0.55.4-5.fc44`) is built without git metadata —
`hyprctl version` there reports commit `unknown`, giving ABI string
`unknown_aq_0.12_hu_0.13_hg_0.5_hc_0.1_hlg_0.6`. nixpkgs' hyprland embeds the real
upstream commit hash instead, so a plugin built the normal way always mismatches,
regardless of build method (confirmed this isn't fixable via `hyprpm` either — the
compositor's own self-reported hash is what's compared against, and Fedora's is
always `unknown` no matter how the plugin was built).

**The fix** (`home/prog/hyprvtb.nix`, done and confirmed working): for
`host == "air"`, build `hyprvtb` against a `pkgs.extend`-overridden `hyprland`
whose `GIT_BRANCH`/`GIT_COMMIT_HASH`/`GIT_COMMIT_DATE`/`GIT_COMMIT_MESSAGE`/
`GIT_TAG` env are all forced to `"unknown"`, matching Fedora's string exactly.
`top` is untouched — it still uses the real hash, matching its own real
nixpkgs-built Hyprland. This forces a full Hyprland compositor rebuild from
source the first time (the version macros are baked into headers used
throughout the codebase, not just a small plugin-facing header) — a one-time
cost; once built it's cached like any other derivation and only rebuilds again
on a nixpkgs bump that touches hyprland.

**Dead end, don't repeat:** tried sidestepping the override entirely by making
air run nixpkgs' own hyprland as the *actual* compositor instead of Fedora's rpm
(`home/pkgs/desktop/wm.nix` + a `/usr/share/wayland-sessions/hyprland-nix.desktop`
entry pointing at `start-hyprland --path ~/.nix-profile/bin/Hyprland`). It
launched, but Hyprland itself crashed on startup (SIGABRT in
`handleUnrecoverableSignal`). The crash report showed DRM/KMS enumeration
succeeding fine against the Apple GPU (`driver apple`, `/dev/dri/card2`, `eDP-1`
mode detection all fine) but then failing to create a GBM allocator:
`Couldn't open a GBM device at fd 27` / `Cannot create a GBM Allocator: gbm
failed to create a device.` — nixpkgs' Mesa doesn't have working Apple Silicon
(Honeykrisp) GBM driver support the way Fedora Asahi's patched Mesa does. Not
fixable without nixGL-style host-Mesa injection (not set up, and fragile even if
it were — aquamarine/wlroots link against nix's own libdrm/pixman/etc, so mixing
in host Mesa risks further ABI mismatches). Reverted both files back to the
override-based fix above.

## Deferred (not in scope right now)

- **Auto-sync systemd timer** (auto-pull + auto-rebuild on both hosts, one shared
  unit keyed off `config.networking.hostName`/`host`) — explicitly deferred; sync
  manually (`git pull` + the `rbhome`/`rbsys` alias) for now. Revisit once the
  shared config is proven out in practice.
- Renaming the OS hostname (`book`) to `air` — not needed, the flake identifies the
  host as `air` independently of the OS-level hostname.
- Re-adding `breeze-square-overlay` to `pkgsAir` (squared Breeze corners on air) —
  skipped for build-time reasons, see above.
- `dnf clean all` / `journalctl --vacuum-size` for more disk headroom — still need
  sudo, still not done. `nix-collect-garbage` (the `trash` alias, no sudo needed
  on air) reclaimed ~4.6G once so far; rerun it before any big rebuild if disk
  gets tight again — check `df -h /` first.
- The 62G root partition itself is just small for this workload long-term; if
  there's slack in the Asahi/APFS container it came from, resizing it would be
  the real fix, but that's a partitioning decision, not something to do
  unprompted.
