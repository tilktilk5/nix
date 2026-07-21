# Plan: per-app titlebar-hosted buttons (hyprvtb), starting with filer

**Date:** 2026-07-20
**Status:** design proposed, NOT started (no hyprvtb code written yet). Handed off
mid-session — the rest of this doc is the context a fresh agent needs to pick it
up cold, not just the plan itself.

## Why this exists

filer's right-edge button strip (sort buttons + file-op buttons) currently lives
*inside* filer's own Qt window content (`filer/qml/Main.qml`, the `rightStrip`
Rectangle) — it visually merges with the real compositor-drawn titlebar
(`hyprvtb`) but isn't actually part of it. The user wants to move buttons like
these into the **real** window titlebar (hyprvtb), as a double-wide bar whose
inner half is program-specific — filer first, then kitty (tabs/splits), and
*maybe* a few Vivaldi actions later.

## Scope decision already made: table Vivaldi's "menu"

Asked about mirroring Vivaldi's File/Edit menu into the titlebar. Answer given
and accepted: **not realistically buildable as a real mirrored menu.** Vivaldi is
closed-source Chromium with no automation API for triggering browser-chrome menu
actions from outside the process. The only real lever is synthesizing the same
keyboard shortcuts Vivaldi already binds (`wtype`/`ydotool` sending Ctrl+T,
Ctrl+W, etc. to the focused window) — gets a handful of common actions as
buttons, not a real menu (no greying-out, no submenus, no dynamic state). If
Vivaldi buttons happen later, scope them as "a few keybind-replay buttons," not
a menu port. Kitty is the easy one — it has a real remote-control protocol
(`kitten @`) built for exactly this.

## The protocol design (v1, minimal — not yet implemented)

- `hyprvtb` opens a Unix socket at `$XDG_RUNTIME_DIR/hyprvtb-buttons.sock`.
- A client app (filer first) connects once at startup and sends
  `REGISTER <pid> id:label|id:label|...` — its own PID plus a small button set
  (single/double-char glyphs, matching the existing close/max/min/pin/rollup
  cell style). **No tooltip support in the titlebar itself for v1** — that's
  compositor-side text rendering scope creep on top of the core ask; add as a
  follow-up once the mechanism is proven.
- Keyed by **PID, not window class** — simplest, and correctly handles multiple
  instances of the same app without a class-matching ambiguity.
- When decorating a window, hyprvtb looks up that window's PID
  (`PHLWINDOW::getPID()`, already used elsewhere in `main.cpp` for the session
  snapshot / relaunch machinery) and, if registered, appends the extra cells
  after the existing 5 system cells (close/max/min/pin/rollup), reusing the
  current draw/hit-test code path (`CVtbDeco::draw()` / `cellAt()` in
  `home/prog/hyprvtb/vtbDeco.cpp` — 1226 lines, not yet read in full; read it
  before touching cell layout).
- A click sends `CLICK <id>` back down that PID's socket.
- Client disconnect (app closes) drops its registration automatically — no
  stale buttons left behind on a crashed/closed client.
- Socket I/O: run on **its own thread** (blocking `accept`/`read`), NOT hooked
  into Hyprland's internal event loop. Hyprland's dev headers weren't
  materialized locally when this was scoped (see below) so the exact
  plugin-facing event-loop-fd API couldn't be verified against real headers —
  guessing at that against a live compositor isn't worth the risk when a plain
  thread is simpler and just as safe. If a future agent DOES verify the
  event-loop-fd API exists and is simple, that'd be the more idiomatic choice —
  just don't guess at the exact call signature without headers in hand.

## The one real risk point — READ BEFORE BUILDING

Writing and building this is safe and fully reversible: it's a `home-manager
switch` rebuild of the plugin `.so`, same as any other package. **Testing it for
real is not** — it requires `hyprctl plugin unload hyprvtb && hyprctl plugin
load ...` to hot-swap it into the live running session. Get this wrong and it
can hang or crash Hyprland, closing every open window on whichever machine you
test on (`top` or `book`/`air` — this plugin is shared, changes affect both).
There IS a safety net: `main.cpp` has session save/restore
(`vtbSaveSession`/`vtbRestoreSession`, bound to Meta+Ctrl+S, auto-restores on a
fresh empty session) that can relaunch windows back to roughly where they were
— but it's not automatic, and it's not a substitute for being careful.
**Confirm with the user before doing the live `hyprctl plugin load` hot-swap** —
building/compiling doesn't need permission, that step does.

## Relevant source locations

- `home/prog/hyprvtb/` — the plugin. `main.cpp` (722 lines, plugin init/lifecycle,
  session snapshot, Lua dispatchers — READ, gives the whole architecture).
  `vtbDeco.hpp`/`vtbDeco.cpp` (186 + 1226 lines — the actual per-window
  decoration: draw, hit-test, mouse handling. NOT yet read in full this
  session — read `cellAt()`, `draw()`/`renderPass()`, and `onMouseButton()`
  before writing the new cell-layout code).
- `home/prog/hyprvtb.nix` — the Nix packaging (`home/prog/hyprvtb/default.nix`
  uses `hyprlandPlugins.mkHyprlandPlugin`). Has the `host == "air"` GIT_*-hash
  override described in `NEXTSTEPS.md` — do not touch that, it's unrelated and
  already fragile/working.
- `filer/qml/Main.qml` — the `OpButton` component + sort-button `Repeater`
  (the `rightStrip` Rectangle) is what would eventually get replaced/emptied
  once buttons move to the real titlebar. Don't rip it out yet — it's the
  reference implementation for what buttons/tooltips to port, and it's the
  live, working UI in the meantime.
- `home/prog/quickshell-files/` — has the proven 220ms/`Easing.OutCubic`
  slide-out idiom (`Behavior on x`, boolean-driven) if the titlebar buttons
  ever want a hover/reveal animation of their own (`Launcher.qml`,
  `OsdWindow.qml`, `SlidePopup.qml`).

## Everything else from this session (context, not part of this plan)

For a fresh agent's situational awareness — these are separate, some already
done, some explicitly deferred:

1. **filer's GPU crash on `book`/air — FIXED, done.** Root cause: nixpkgs' Qt
   links against nixpkgs' Mesa, which has no working Apple Silicon (Honeykrisp)
   GBM/EGL driver on this machine (same root cause already diagnosed for
   hyprvtb/Hyprland itself in `NEXTSTEPS.md`). Fix in `home/prog/filer.nix`:
   `host == "air"` now builds filer as a plain wrapper exec-ing the **system**
   `/usr/bin/python3` + dnf-installed `python3-pyside6` (Fedora's own Meso,
   proven working — it's what quickshell/Hyprland already run against). `top`
   is untouched (still the original nixpkgs-Qt `stdenv.mkDerivation` build).
   **`sudo dnf install python3-pyside6` was run and is done on this machine.**
   Confirmed stable across repeated launches. **This edit is still uncommitted**
   (`git status`: `M home/prog/filer.nix`) — the user hasn't asked for a commit
   yet.
   - Gotcha hit once: a `home-manager switch --flake /home/lam/nix#air` run
     appeared to succeed but didn't actually pick up this edit (deployed
     generation still resolved to the old nixpkgs-Qt derivation, confirmed via
     `readlink -f $(which filer)` showing `filer-live` not `filer`). Re-running
     the same switch command a second time picked it up correctly. Cause not
     fully root-caused — if `filer` ever mysteriously reverts to crashing
     again, check `readlink -f $(which filer)`: it should point at a plain
     `.../filer/bin/filer` (a `writeShellScriptBin` output, tiny wrapper, no
     `QT_PLUGIN_PATH` exports) — if it instead shows heavy Qt env-var exports
     and a `filer-live` path segment, `air` is back on the wrong (nixpkgs-Qt)
     build; just rerun the switch.
2. **filer UI changes — done, uncommitted** (`git status`: `M filer/qml/Main.qml`):
   - Removed the "created" date column from the file list rows (kept the
     `created` sort option, just not displayed).
   - Added themed tooltips (Theme colours, `PixelText`, not native Qt styling)
     to all 10 right-strip buttons (3 sort + 7 op buttons), via real
     `QtQuick.Controls.Basic` `ToolTip` Popups (renders on the window's overlay
     layer, no z-order fighting with the file list — confirmed available in
     both `top`'s nixpkgs Qt and `air`'s system Qt).
   - Tooltip slide-out animation: **first attempt was broken** (mixed a Popup
     `enter`/`exit` `Transition` with a permanent `x` binding on the same
     property — they fight each other every frame). Fixed to use `Behavior on
     x` with `x` driven by an `armed` boolean + a delay `Timer`, matching the
     exact idiom the panel's own edge-reveal widgets use
     (`Launcher.qml`/`OsdWindow.qml`/`SlidePopup.qml`: `Behavior on x`,
     `x: cond ? shown : hidden`, 220ms, `Easing.OutCubic`).
   - **KNOWN BUG, explicitly deferred by the user ("we'll get to that
     later")**: the tooltip does not smoothly *un*-slide — it gets stuck near
     its open position and stays visible for a bit before disappearing,
     instead of sliding back in symmetrically with the open animation. Not
     diagnosed yet. Likely candidates worth checking first: the `visible:
     armed || x < -1` condition combined with the `Popup`'s own internal
     open/close transition timing (Popup closing may unparent/hide before the
     `Behavior` finishes, or the `-1` threshold interacts oddly with
     `Behavior`'s per-frame easing curve landing asymptotically rather than
     exactly at 0). Reproducible in both `OpButton`'s tooltip and the sort
     buttons' tooltip (same code pattern, copy-pasted).
3. **File/video previews — DESIGN NOT FINALIZED, questions never answered.**
   User wants something more interesting than a plain grid/list toggle: a
   **hybrid list/grid view** where images and videos appear as thumbnails at
   the top of the directory they're in (not just a separate mode). Three
   concrete open questions were queued (asked once via a UI tool, user
   interrupted before answering and asked to clarify via chat instead — then
   the conversation moved on to the titlebar-buttons topic before circling
   back). Re-ask a fresh agent should raise before implementing:
   - **Nesting scope**: does an expanded subdirectory (tree `+`/`−` toggle) get
     its own thumbnail strip at the top of ITS rows too, or only the top-level
     open directory?
   - **Row dedup**: once a file shows as a thumbnail, does it still also appear
     as a normal sortable list row further down, or is the row replaced
     entirely (thumbnail is its only appearance)?
   - **Strip layout**: wrapping grid (fills available width, grows vertically
     with media count) vs. a fixed-height horizontal filmstrip.
   - Backend notes gathered but not committed to: `ffmpeg` is already available
     on this machine (`/home/lam/.nix-profile/bin/ffmpeg`) for video frame
     grabs; `~/.cache/thumbnails/{large,normal,x-large,xx-large}` already exists
     (freedesktop thumbnail cache convention, likely already partially
     populated by KDE's own thumbnailers) — worth reading from/writing to that
     cache rather than inventing a separate one, so filer doesn't duplicate
     what Dolphin/etc. already generated. Qt's native `Image` type handles
     still images essentially for free (just cap `sourceSize` so a huge RAW
     doesn't stall the UI thread). `FileOps` (`filer/main.py`) is the natural
     home for any new backend Slot (thumbnail generation needs to be async —
     same `QProcess` pattern `FileOps.run` already uses, never block the UI
     thread).
4. **Repo/workflow facts confirmed this session** (already documented in
   `AGENTS.md`/`NEXTSTEPS.md`, restated here since they're load-bearing for
   whatever comes next):
   - `filer/main.py` and all of `filer/qml/*` are unconditional/shared — both
     `top` and `book` exec the exact same live source file at
     `/home/lam/nix/filer/`. Only the *runtime* (which Python/Qt executes it)
     differs per host, via `home/prog/filer.nix`'s `host` branch. Any UI/logic
     edit applies to both machines immediately on save, no rebuild needed on
     either side.
   - `git pull` on `book`/air picked up a new **private** git submodule
     (`sounds/` → `github.com/tilktilk5/vista-sounds`) cleanly this session —
     `git submodule update --init` worked without a credential prompt (auth
     already configured on this machine).
   - `home-manager switch --flake /home/lam/nix#air` is the `rbhome` for this
     machine (standalone home-manager, not a NixOS module — unlike `top`,
     where `rbhome`/`rbsys`/`update` are all `sudo nixos-rebuild switch
     --flake .../#top`, per `AGENTS.md`).
   - `sudo -A dnf install ...` works on this machine for non-interactive sudo
     from an agent session — `SUDO_ASKPASS` is already set and `ksshaskpass`
     is installed, so `sudo -A` pops a real GUI password prompt instead of
     failing. Useful to know before assuming "sudo needs a real terminal" like
     `NEXTSTEPS.md` says for plain `sudo`/`dnf` (that note predates discovering
     `-A` works here).

## Suggested first steps for whoever picks this up

1. Read `vtbDeco.cpp`'s `cellAt()`, `draw()`/`renderPass()`, and
   `onMouseButton()` in full (not yet done this session) before writing
   anything — the new cells need to slot into that existing layout/hit-test
   code, not duplicate it.
2. Try to actually get Hyprland's dev headers locally (a `nix build` against
   `home/prog/hyprvtb/default.nix` with `keep-going`/`--print-build-logs`, or
   locate wherever `hyprlandPlugins.mkHyprlandPlugin` unpacks the source it
   builds against) so the socket/thread integration can be checked against the
   real API instead of assumptions.
3. Write the socket server + registration/click protocol, build via
   `home-manager switch --flake /home/lam/nix#air` (safe, just compiles).
4. **Stop and confirm with the user before the first live `hyprctl plugin
   unload`/`load` test.**
5. Wire filer as the first client once the plugin side is confirmed working.
