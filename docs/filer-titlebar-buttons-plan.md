# Plan: per-app titlebar-hosted buttons (hyprvtb), starting with filer

**Date:** 2026-07-20
**Status:** IMPLEMENTED (same day, follow-up session). What shipped, where:

- **hyprvtb double-wide bar + socket** — every window's bar is now two columns
  wide: inner column = app-registered buttons (empty if none), outer column =
  the five system cells + stacked title. `vtbIpc.{hpp,cpp}` is the socket
  server (`$XDG_RUNTIME_DIR/hyprvtb-buttons.sock`, REGISTER/FOOTER in,
  CLICK out, keyed by PID, dedicated I/O thread — doLater/doOnReadable were
  checked against the 0.55.4 source and are NOT thread-safe, hence the thread
  + atomic-serial + damage-from-main-thread-hooks design). Buttons carry
  per-entry state (normal / lit / disabled), `-` entries are spacers, FOOTER
  draws stacked text at the inner column's bottom.
- **Python client** — `~/nix/pylib/vtbclient.py` (reconnecting daemon thread,
  used by filer, surfer, and kitty's helper).
- **filer** — right strip deleted from `filer/qml/Main.qml`; buttons register
  via the `Titlebar` bridge in `filer/main.py` (labels/states re-push on any
  view-state change; dir size rides FOOTER). NB: button ids must not contain
  ':' (protocol separator — bit us once with "sort:name").
- **tooltips** — implemented compositor-side after all (plugin 2.23): hover a
  cell ~450ms and a themed label pops out left of the bar; system cells have
  fixed strings, app buttons pass theirs as the optional 4th REGISTER field.
  No timers: the dwell check rides the mouse-move hook, so a perfectly
  motionless cursor shows the tip on its next 1px twitch. The old QML tooltip
  un-slide bug died with the strip.
- **kitty** — `~/nix/pylib/kitty-vtb.py`, launched per-instance by
  `startup_session vtb.session` (kitty.conf), maps titlebar buttons to
  `kitten @ --to $KITTY_LISTEN_ON`: vsplit/hsplit (forces `splits` layout),
  zoom (toggle stack), close split, copy/paste, new/next tab, scrollback.
- **surfer** — NEW browser at `~/nix/surfer` (PySide6 + QtWebEngine = open
  Chromium; the Vivaldi keybind-replay idea was dropped in favour of this).
  Tabs, themed address bar, persistent profile; back/fwd/reload/tab/copy-url
  buttons live in the titlebar. Packaged by `home/prog/surfer.nix` (same
  air/system-python split as filer.nix). Verified rendering on air.

**Night-2 fixes (plugin 2.24, deployed, loads at next login):**

- **Tooltips/stale-label root cause**: damage was driven only by mouse-move
  events, so a motionless cursor never saw the tooltip dwell fire and a
  clicked sort button's `↑/↓` label stayed stale until the pointer moved.
  Fixed with a 150ms main-thread `CEventLoopTimer` heartbeat (same re-arm
  pattern as Hyprland's ANRManager; removed in PLUGIN_EXIT before dlclose) —
  it damages bars whose registration serial moved and pops tooltips after
  their 450ms dwell. This also covers spontaneous app updates (surfer's
  reload→stop label while loading finishes with no input).
- Lit app cells now grey to the inactive tone on unfocused windows, matching
  the old strip's `win.fgAccent`.
- **kitty gotcha**: a compositor-spawned kitty (minimal env) does NOT inject
  `KITTY_LISTEN_ON` into startup-session background children — reproduced
  with `env -i ... kitty --detach`. That's why login kitties had no buttons
  while shell-launched ones did. `pylib/kitty-vtb.py` now falls back to the
  parent PID's socket, waits for the socket file, and logs to
  `~/.local/state/vtb/kitty-vtb.log`.
- **hyprctl plugin unload/load under the lua config** — re-examined against the
  0.55.4 source (`plugins/PluginSystem.cpp`, `config/lua/ConfigManager.cpp`).
  `unloadPlugin` runs PLUGIN_EXIT + dlclose, then schedules `Config reload`;
  the reload re-runs hyprland.lua's `hl.plugin.load(<symlink>)`, and
  `updateConfigPlugins` re-loads any config plugin not currently loaded. So a
  bare `hyprctl plugin unload <symlink>` DOES trigger an automatic re-load from
  the symlink. The earlier "same version stays" was because the symlink still
  resolved to the same store path at that moment (dlopen returns the cached
  image for an identical path). Now that home-manager repoints the symlink to a
  genuinely new store path on each build, `dlopen(<symlink>)` maps the new file
  → the reload picks up the new version. Caveat: unload→dlclose→reload only
  stays up if PLUGIN_EXIT tears everything down cleanly (IPC thread joined,
  timer removed, decorations + render-stage hooks removed) — a botched teardown
  crashes the whole compositor, so it's riskier than a logout even though it
  should work. `p->m_path` is stored verbatim (no realpath), so unload must be
  called with the SAME symlink path the lua used, not the resolved store path.

**Night-3 fixes (plugin 2.25, deployed, loads at next login):**

- **Tooltips never actually appeared — real root cause found.** The 2.24
  timer heartbeat was firing fine (verified against the 0.55.4 source:
  `onTimerFire` only calls a timer with `strongRef() > 2`, and we hold the
  3rd ref via `g_pGlobalState->tick`; `updateTimeout` from inside the cb
  re-arms via `scheduleRecalc`). The bug was the render LAYER: the bar is a
  `DECORATION_LAYER_UNDER` decoration, which Hyprland draws *before* the
  window surface (`Renderer.cpp` ~657 UNDER, then the window surface). The
  bar itself is safe — it sits in reserved space to the window's right — but
  the tooltip pops out LEFT, over the window's own area, so the opaque window
  surface painted straight over it. It was never visible, on any app.
  Fix: the tooltip is now its own pass element enqueued at
  `RENDER_POST_WINDOWS` (over windows, under top/overlay layers) via
  `enqueueTooltip`/`drawTooltipPass`; `mainThreadTick` pre-sizes
  `m_tooltipBox` so the element's boundingBox already claims the strip on the
  first frame (else `simplify()` treats it as window-occluded and discards).
  System cells + all three apps (filer/kitty/surfer) get tooltips now.
- **kitty vertical-split `|` label was blank.** The old `_clean()` replaced
  `:` and `|` (the wire separators) with a space, so a `|`/`:` glyph label
  was destroyed in transit. Replaced with percent-encoding in
  `pylib/vtbclient.py` (`%3A`/`%7C`/`%0A`, `%` escaped first; non-ASCII glyphs
  like `↑ » …` pass through) and a matching `pctDecode` in the plugin's
  `vtbIpc.cpp`. Labels/tooltips may now hold any character.

**Also fixed (kitty theme colours on Meta+W):** `kitty-focus-dim.py` restored a
focused terminal with `set-colors --reset`, which implies `--configured` and so
rewrites kitty's *configured* defaults to the values they had at kitty STARTUP.
After that, wal-set.sh's `SIGUSR1` live reload can no longer change kitty's
colours, so a theme switch left the text stuck on the launch-time palette
(confirmed: a kitty whose startup fg was `#cc060c` ignored a reload to
`#b7b7cc`). Fixed by restoring focus with an explicit `foreground=<accent>` read
live from `theme.conf` (a plain, non-configured override that a reload correctly
supersedes — verified reload beats a non-`--configured` override). Takes effect
for kitties opened after the next login; already-pinned running kitties need a
restart (or heal on their next focus change) to fully re-sync.

**Night-4 fixes (plugin 2.26, deployed, loads at next login):**

- **Tooltips slide in/out.** Tooltips were static pop-ins; now they slide in
  from the left with a fade (OutCubic, 220ms — matching quickshell's
  `SlidePopup` card slide) and retract the same way. `renderTooltip` advances a
  time-based phase itself and re-damages until it settles, so it animates even
  on a motionless cursor; `m_ttWantShown`/`m_ttPhase`/`m_ttCell` hold the state,
  `hideTooltip()` now *requests* a retract (teardown happens when the phase hits
  0). Slides from the left (never reaches the bar) so no clipping is needed —
  `renderRect`/`renderTexture` reset scissor to their own damage internally, so
  a pre-set clip box would be ignored anyway.
- **Inner-column spacers removed (all apps).** Dropped the `"-"` group spacers
  from filer (`filer/qml/Main.qml`), kitty (`pylib/kitty-vtb.py`), and surfer
  (`surfer/qml/Main.qml`) — the columns read cleaner as one uniform grid.
- **Equal column/row spacing.** The two button columns are now laid out as ONE
  grid centered in the double-wide bar, with the inter-COLUMN gap equal to the
  inter-ROW gap (`VTB_CELL_GAP`) and matching side margins. New helpers in
  `vtbDeco.cpp` (`gridLeftMargin`/`innerColX`/`sysColX`/`titleTexX`/
  `footerTexX`) are the single source of truth for both drawing and hit-testing
  (replaced the old `VTB_PAD` / `colW()+VTB_PAD` column offsets everywhere).

**Quickshell (hot-reloaded live, no login needed):**

- **Widgets fan out at login.** `shell.qml`'s `applyWidgetState` used to pin the
  saved set instantly; it now fans them OUT (the same staged cascade the reveal
  button uses) on a genuine login, and snaps them on instantly for hot reloads
  (a `$XDG_RUNTIME_DIR/qs-fanned` marker — wiped on logout — distinguishes the
  two, so wallpaper-change reloads don't replay the ~1.2s fan). The set is the
  saved pins (`~/.local/state/quickshell/widgets`, written by Meta+Ctrl+S), and
  falls back to a declarative `_defaultWidgets` persist-key list for first boot
  — a one-line edit to change, and host-specific defaults can be added there
  later without touching the fan logic. Current saved set: `clock weather disk
  cpu eth` (captured from the live session via `qs ipc call widgets save`).
- **Battery charging indicator.** `StatusPanel.qml`'s battery module now flips
  its label `bat` → `chg` while charging (on top of the existing green value
  colour, which alone was easy to miss near full charge).

**Night-5 fixes (plugin 2.27, deployed, loads at next login):**

- **Tooltip now slides OUT of the bar, not in from nowhere.** Reversed the slide
  direction in `renderTooltip`: the label starts fully tucked behind the bar
  (shoved `W + gap` right) and slides left out of the bar's edge, like the
  quickshell widgets emerge from the screen edge. The un-emerged part is clipped
  to the bar's left edge — `renderRect`/`renderTexture` reset the GL scissor to
  their own damage internally, so the clip is passed as a `damage` region via
  `SRectRenderData`/`STextureRenderData` (both have a `const CRegion* damage`
  field) rather than a manual scissor. Dropped the fade (a pure slide, like the
  widgets).
- **Click-activation flash on every titlebar button.** A pressed cell (system or
  app, and on the shaded floating bar) inverts for `VTB_FLASH_MS` (220ms) — the
  cell fills solid with its highlight colour and the glyph is drawn in the bar
  background — then reverts. Driven by `m_flashCell`/`m_flashAt` + `flashCell()`,
  set from `handleDownEvent`/`handleRolledDown`; `renderPass` self-damages while
  the flash plays. close/minimize also close/hide the window so their flash just
  isn't seen — everything else (maximize/pin/rollup/sort/copy/…) confirms.

**Hyprland single-workspace fix (`hypr-files/hyprland.lua` + the live
`~/.config/hypr/hyprland.lua`, takes effect next login):**

- Removed the startup `hyprctl dispatch focus workspace 50`. The hyprvtb plugin
  relaunches the saved session during config load (`hl.plugin.load`), and those
  windows map onto the default workspace 1 — but the async `focus workspace 50`
  raced that mapping, so windows that mapped before the switch stayed on 1 and
  ones after landed on 50. Result: a fresh login scattered programs across two
  workspaces, some only reachable via their taskbar icon. The desktop is locked
  to a single workspace (all workspace binds/gestures already removed), so the
  anchor-at-50 leftover from the abandoned scroll-to-create scheme just had to
  go. NB `hyprland.lua` is seeded once (wal-set.sh rewrites its colours in
  place), so `home-manager switch` does NOT redeploy it — the live copy was
  edited directly to match the repo.

Still open: surfer polish (tab-close reloads later tabs via the Repeater
rebuild; no default-browser registration yet).

**Night-6: surfer browser overhaul — titlebar-native chrome (plugin 2.28,
deployed, loads at next login; surfer runs live source so its half is already
live):**

The whole browser chrome moved into the titlebar. Two new plugin capabilities
back it, both added to the app-button IPC (see `vtbIpc.hpp` for the wire doc):

- **Editable title = address bar (in-plugin text editor).** An app opts its
  title region in with `TITLEEDIT 1`. Clicking the stacked title (outer column,
  below the system cells) enters an in-bar editor: `CVtbDeco` grabs the keyboard
  via a new `input.keyboard.key` bus listener (`onKeyboardKey`) — cancellable, so
  `info.cancelled` swallows the key before keybinds AND the focused client —
  translates keycodes with `xkb_state_key_get_one_sym/utf8` (xkb keycode =
  libinput `+ 8`) off `g_pSeatManager->m_keyboard`'s `m_xkbState`, and edits an
  internal UTF-8 buffer with a caret drawn between the vertical codepoint rows.
  Enter submits (`ADDR <text>` back to the client), Esc cancels. Click-to-edit
  selects the whole field (browser style); the first keystroke replaces it.
  Ctrl/Alt/Super combos pass straight through so compositor shortcuts still work.
  The grab is gated hard on `PWINDOW == focusState()->window()` (both in
  `onKeyboardKey` and `renderPass`) so it can NEVER eat keystrokes meant for
  another window. surfer sets `win.title` to the live URL, so the bar shows the
  address and the editor seeds from it. Known v1 limits: no key-repeat (the grab
  swallows the press so the client's repeat never starts), no paste (reading the
  Wayland clipboard from the compositor is async/involved), long URLs anchor at
  the start with the caret clamped to the visible run.
- **Tabs as draggable app-buttons.** App-button clicks now fire on RELEASE (was
  press) so a press+drag can reorder instead: a `drag` 5th REGISTER field marks a
  button reorderable; dragging it past a threshold tracks the nearest draggable
  slot and, on drop, sends `REORDER <srcId> <dstId>`; a release without a drag is
  the normal click. `-` separators now render as a thin divider line (not just a
  gap). This applies to every client, but only surfer marks buttons draggable.
- **WAKE.** Rolling a window back down un-hides its surface (`setHidden(false)`),
  and QtWebEngine presents black until it redraws — so `toggleRollup`'s unroll
  path sends `WAKE` to the owning client. (Not sent on un-minimize: minimize
  slides the window off-screen rather than hiding the surface.)

surfer side (`surfer/main.py` + `surfer/qml/Main.qml`, live source — no rebuild):

- Removed the in-window header + tab strip entirely; the window is pure page.
- Chrome registered in the inner column: `back / fwd / reload / copyurl`, a `-`
  separator, one draggable `tab:<tid>` button per tab (2-letter label from the
  page title, lit when active), then `+t` new-tab at the bottom. Clicking the
  ACTIVE tab again closes it; dragging reorders (`onReordered` → `tabs.move`).
  Tabs carry a stable `tid` so button ids and the active pointer survive
  reorder/close.
- `Titlebar` bridge gained `reordered`/`addrSubmitted`/`wake` signals (queued off
  the VtbClient I/O thread) and `setTitleEdit`. `onAddrSubmitted` navigates the
  current tab; `onWake` pulses `win.nudging` (hide+show the live view for 32ms)
  to kick QtWebEngine out of its black state.
- **Session persistence:** a `Session` QObject saves open tab URLs + the active
  index to `$XDG_STATE_HOME/surfer/session.json` on close and restores them on
  launch (unless a URL arg is passed).

vtbclient.py mirrors all of it: the `drag` 5th field, `set_title_edit`, and
`on_reorder`/`on_addr`/`on_wake` callbacks (resent on reconnect).

The original design notes below are kept for reference.

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
