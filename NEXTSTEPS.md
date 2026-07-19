# NEXTSTEPS — Share this config across desktop (`top`) + MacBook Air (`air`), with git auto-sync

> Status: **planned, not yet implemented.** Nothing in here has been applied. `top` is
> untouched. Each phase is written so `top` never breaks; verify after every phase.

## Context / goal

The Hyprland/Quickshell rice here originally came from a Fedora Asahi MacBook Air and was
migrated into this flake. Goal: run **both machines from this one repo**
(`github.com/tilktilk5/nix`, branch `main`) so a push from either machine — by me or an
agent — automatically reflects on the other.

Decisions made:
- **MBA OS = NixOS on Asahi** (aarch64) via the `apple-silicon-support` flake → full
  multi-host flake, not just home/dotfile sharing.
- **Auto-sync = pull + auto-rebuild** on a timer; pushes stay manual; local uncommitted
  edits are auto-stashed so nothing in-progress is clobbered.
- **Do the desktop side first.** The MBA isn't installed yet, so everything below is built
  and tested on `top`. The actual Asahi install + generating the MBA's real
  `hardware-configuration.nix` is a follow-up done on the laptop.

### Current-state facts that shape the plan
- `flake.nix` is single-host: `system` hardcoded to `x86_64-linux`, one global `pkgs`.
- `sys/default.nix`'s `umport` auto-imports **every** `.nix` under `sys/` → `sys/hw/nvidia.nix`,
  `sys/gme/steam.nix`, and the bootloader/kernel/CUDA-substituter parts of `sys/base.nix`
  currently apply to *any* host. These must become per-host.
- Reusable pattern: `my.aerotheme.enable` (in `sys/options.nix`) consumed with `lib.mkIf`
  in `sys/dsk/plasma.nix` — the same mechanism guards hardware modules per host.
- **Rice delivery asymmetry (important):** `home/prog/hyprland.nix` seeds `hyprland.lua`
  as a **writable copy, only if absent** (`install … || true` in
  `home.activation.seedHyprMutableFiles`); `home/prog/quickshell.nix` seeds `Theme.qml` the
  same way but ships all other `*.qml` as **read-only store symlinks**. So editing the shared
  `hyprland.lua` *template* does NOT touch `top`'s already-seeded live file (its scale stays
  `1`), while `SysInfo.qml`/`Osd.qml` edits propagate to both hosts. This is why scale uses a
  generated per-host param and brightness uses runtime detection.
- Laptop-hostile bits are localized: `scale = "1"` (Retina wants ~2), brightness via
  `ddcutil` (external monitor) instead of a real backlight, `no_hardware_cursors` (NVIDIA,
  harmless elsewhere). Wallpaper scripts already query `hyprctl monitors -j` dynamically.

---

## Phase 1 — Options scaffold (`sys/options.nix`), no behavior change
Add alongside `my.aerotheme.enable`:
- `my.host.role` : enum `[ "desktop" "laptop" ]`, default `"desktop"`.
- `my.hardware.nvidia.enable`, `my.hardware.appleSilicon.enable` : `mkEnableOption` (default false).
- `my.gaming.enable` : `mkEnableOption`.
- `my.rice.monitorScale` : str, default `"1"` (consumed by the home layer in Phase 5).

Nothing consumes them yet; defaults keep every host behaving as today.

## Phase 2 — Guard machine-specific modules with `lib.mkIf` (keep umport)
Files stay in the tree; they become no-ops when their toggle is off.
- `sys/hw/nvidia.nix` → wrap whole body in `lib.mkIf config.my.hardware.nvidia.enable`.
- `sys/gme/steam.nix` → wrap in `lib.mkIf config.my.gaming.enable`.
- `sys/base.nix` → gate the CUDA/ai cachix `trusted-substituters`/`-public-keys` behind
  `lib.mkIf (config.my.host.role == "desktop")`; demote `boot.kernelPackages` to
  `lib.mkDefault pkgs.linuxPackages_latest` and `efi.canTouchEfiVariables` to
  `lib.mkDefault true` so the Asahi host can override. Keep `nix`/`gc`/`time`/`i18n`/
  `networkmanager`/`stateVersion` global.
- `hosts/top/configuration.nix` → add explicit opt-ins (net-zero for `top`):
  `my.host.role = "desktop"; my.hardware.nvidia.enable = true; my.gaming.enable = true;
  my.rice.monitorScale = "1";`

**Gate:** `nixos-rebuild build --flake .#top` toplevel drv identical to pre-change.

## Phase 3 — Multi-arch flake refactor + `air` output (`flake.nix`)
- Add input `apple-silicon-support = { url = "github:tpwrules/nixos-apple-silicon";
  inputs.nixpkgs.follows = "nixpkgs"; }`. (Fallback if a mesa/kernel bump breaks the build:
  drop the `follows` so it uses its own tested nixpkgs.)
- Replace single `system`/`pkgs` with `pkgsFor = system: overlays: import nixpkgs
  { inherit system; config.allowUnfree = true; overlays; };` then
  `pkgsTop = pkgsFor "x86_64-linux" [vcv-rack-overlay ollama-overlay]` and
  `pkgsAir = pkgsFor "aarch64-linux" [vcv-rack-overlay]` (NO CUDA overlay on aarch64).
- `nixosConfigurations.top`: unchanged except `inputs.tuxmanager.packages.${system}` →
  `…packages."x86_64-linux"` (only forced line; behavior identical).
- Add `nixosConfigurations.air` (aarch64): overlay module with `[vcv-rack-overlay]` only,
  `apple-silicon-support.nixosModules.default`, `./hosts/air/configuration.nix`, home-manager
  NixOS block (same shape as `top`, `useGlobalPkgs = true`) — **no** CUDA/ollama/tuxmanager/aerotheme.
- `homeConfigurations`: keep `"lam"` (→ `pkgsTop`); add `"lam@air"` (→ `pkgsAir`) so standalone
  `rbhome` works on the MBA and feeds `hyprvtb` aarch64 pkgs.

## Phase 4 — `hosts/air/` (evaluatable placeholder now; real HW config on MBA later)
- `hosts/air/configuration.nix`: `imports = [ ./hardware-configuration.nix ../../sys ];`
  `networking.hostName = "air"; my.host.role = "laptop";
  my.hardware.appleSilicon.enable = true; my.rice.monitorScale = "2";`
  `boot.loader.efi.canTouchEfiVariables = false;` + a `hardware.asahi` block
  (`peripheralFirmwareDirectory` placeholder, `useExperimentalGPUDriver = true`,
  `experimentalGPUInstallMode = "replace"`); pipewire/printing/rtkit; omit vmware/openrgb/CUDA.
- `hosts/air/hardware-configuration.nix`: documented PLACEHOLDER with
  `nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";` + a stub `fileSystems."/"` so `.#air`
  *evaluates* on the desktop. Regenerated on the MBA via `nixos-generate-config`.

## Phase 5 — Per-host rice shim (minimal; `top` unchanged)
- **Scale via generated param.** New `home/prog/hypr-host.nix` renders read-only
  `~/.config/hypr/host.lua` = `return { scale = "<my.rice.monitorScale>", laptop = <bool> }`
  from `osConfig.my.rice.*` (standalone fallback). One-line top-safe edit to the shared
  `home/prog/hypr-files/hyprland.lua` monitor block: `dofile` `host.lua` with `scale or "1"`
  fallback. `top`'s already-seeded `hyprland.lua` is untouched (stays scale 1); only a fresh
  seed (the MBA) gets scale 2.
- **Brightness via runtime detection.** Edit `home/prog/quickshell-files/SysInfo.qml` (mirror
  in `Osd.qml`): probe `/sys/class/backlight` — non-empty → `brightnessctl` (drop the ~1.5s DDC
  debounce); empty → keep existing `ddcutil setvcp/getvcp 10` path verbatim. `top` has no
  backlight → ddcutil path → identical behavior.
- `Theme.qml` (`barWidth=48`, pixel fonts) needs **no** change: QtWayland layer-shell surfaces
  honor the compositor `wl_output` scale, so Hyprland `scale=2` auto-scales the panel. Verify
  on the MBA; add a per-host `barWidth` only if it proves wrong.
- Leave `no_hardware_cursors` / trackball / touchpad blocks (harmless / no-ops on the MBA).

## Phase 6 — Auto-pull + auto-rebuild systemd unit (one shared unit, both hosts)
New `sys/auto-sync.nix` (umport picks it up → both hosts). `oneshot` service + timer;
`host = config.networking.hostName` baked in so the same unit rebuilds `.#top` on top and
`.#air` on air. Script: fetch as user `lam` (`runuser -u lam`), compare `@` vs `origin/main`,
if behind `git pull --rebase --autostash`, then `nixos-rebuild switch --flake <repo>#<host>`
as root; `notify-send` (via `runuser`) on pull-conflict or build failure. Switch is atomic →
a failed build stays on the current generation. Timer: `OnBootSec=5min`,
`OnUnitActiveSec=30min`, `Persistent=true`, `RandomizedDelaySec=2min`. Auth: prefer the
**public HTTPS** remote (no creds) else a read-only deploy key under `/home/lam/.ssh/`.
No auto-push.

Also edit `home/prog/zsh.nix` aliases: `rbsys`/`update` → `--flake /home/lam/nix/#$(hostname)`;
keep `rbhome = …#lam` (use `#lam@air` on the MBA).

## Phase 7 — Docs / consolidation
Leave `~/nixos-migration` as read-only historical reference (its NOTES.md/CLAUDE.md guidance is
already captured). Update `AGENTS.md`: two hosts, the new `my.host.role`/`my.hardware.*`/
`my.gaming.*`/`my.rice.*` gates over umport, the `hosts/air/` placeholder workflow, the
`host.lua` + runtime-backlight rice shim, and the `nix-autosync` timer.

---

## Verification (run from repo root after each phase)
- **P1/P2:** `nix flake check`; `nixos-rebuild build --flake .#top` → toplevel drv identical to
  a pre-change build (the "didn't break top" gate).
- **P3:** `nix flake check`; rebuild `.#top`; `home-manager build --flake .#lam`.
- **P4:** `nix eval .#nixosConfigurations.air.config.system.build.toplevel.drvPath` (cross-arch
  eval); `nix build .#nixosConfigurations.air…toplevel --dry-run` shows it wants the Asahi
  kernel/firmware + an aarch64 builder.
- **P5:** rebuild `.#top`; confirm `~/.config/hypr/hyprland.lua` unchanged (seed skip) and
  `host.lua` renders `scale="1"`; confirm `top` brightness still uses ddcutil.
- **P6:** rebuild `.#top`; `systemctl status nix-autosync.timer`; `systemctl start
  nix-autosync.service` once → journal says "up to date" when in sync; `rbsys` expands to `#top`.

**Requires the MBA (follow-up, not doable from the desktop):** installing NixOS-on-Asahi,
extracting peripheral firmware from macOS, generating the real
`hosts/air/hardware-configuration.nix`, first `nixos-rebuild switch --flake .#air`,
GPU/mesa-asahi bring-up, and visually confirming `scale=2` + brightnessctl backlight + panel
auto-scaling. All commits go to this one repo; the auto-sync timer then keeps both machines
converged.

## Risks
- `apple-silicon-support` tracks nixpkgs closely; a kernel/mesa bump can occasionally break the
  build — fallback is to unpin its `nixpkgs.follows`.
- Auto-rebuild is atomic (failed build → stays on current generation + notifies), so a bad push
  is recoverable; a build that *succeeds but misbehaves* still needs a manual
  `nixos-rebuild switch --rollback`.
- `--autostash` preserves in-progress edits; per `AGENTS.md` the unit aborts + notifies on a
  reapply conflict rather than discarding anything.

## Files this will touch
`flake.nix`, `sys/options.nix`, `sys/base.nix`, `sys/hw/nvidia.nix`, `sys/gme/steam.nix`,
`hosts/top/configuration.nix`, `hosts/air/{configuration,hardware-configuration}.nix` (new),
`sys/auto-sync.nix` (new), `home/prog/hypr-host.nix` (new),
`home/prog/hypr-files/hyprland.lua`, `home/prog/quickshell-files/{SysInfo,Osd}.qml`,
`home/prog/zsh.nix`, `AGENTS.md`.
