# System Settings menu-bar visibility probe

> Track / 关注：[GitHub issue #36](https://github.com/jizhi0v0/macos27-beta-issues/issues/36)

On this Mac running macOS 27.3 beta 1 (26C5035r), DuoShot's failure to obey
System Settings → Menu Bar follows its installation context. Changing its
menu-bar implementation is not supported by these experiments.

The decisive control uses the **existing installed bundle without rebuilding,
editing Info.plist, changing entitlements, or re-signing**. Copies in this
repository's ignored `build/` directory obey the switch. Fresh instances from
`/Applications/DuoShot.app` and `/Applications/DuoShot Menu Bar Test.app` do not.
This isolates a system-side application association/visibility-management
problem in the tested environment. It does not identify the faulty private
database field, or establish which macOS version introduced it.

## Recorded result, 2026-11-12–13

Full evidence: [baseline notes](../../baselines/27.3-beta1-26C5035r/menu-bar-visibility/README.md).
Apple describes this switch as controlling whether an application's menu-bar
icons appear: [Menu Bar settings](https://support.apple.com/en-asia/guide/mac-help/mchlad96d366/mac).

- All seven minimal variants below hide and reappear through the real system
  switch. The combined AppKit variant passed three off/on rounds.
- A minimal variant using DuoShot's bundle ID, Developer ID signing identity,
  audio-input entitlement, and early window/drop setup also works. Older SDK
  linkage metadata and the installed Info.plist fields do not reproduce the
  failure in the test directory.
- The original installed instance fails three rounds. Recreating its status
  item, restarting MenuBarAgent, and launching another process from the original
  path do not resolve it.
- An unchanged installed bundle copied to `build/FullDuoShot.app` passes three
  rounds. Another unchanged copy at `build/DuoShot.app` passes two rounds.
  Both copies' four bundle files are byte-identical to the original, including
  its executable and signature; see `bundle-comparison.json` in the baseline.
- Between those passing controls, a fresh original-path process fails two
  rounds, and the unchanged copy under a different name in `/Applications`
  fails two rounds. The temporary `/Applications` copy was removed afterward.

The user's existing DuoShot process and screenshot editor were preserved.
Test processes exited, and the system switch, app's Show menu bar icon switch,
and Allow command-line capture switch were restored to on. No source in
DuoShot, DuoPaste, or DuoSub was changed. No system preference file was edited.

## Minimal variants

```sh
zsh tools/menu-bar-visibility/build.sh
open -g tools/menu-bar-visibility/build/MBHPlain.app
```

The seven bundles use the same SDK, minimum OS, ad-hoc signing method, and
button image. The AppKit variants share the same status-item implementation:

- `MBHPlain`: `NSApplication.run()`, `NSStatusItem`, `NSMenu`.
- `MBHDrop`: plain plus DuoShot's constrained drag-destination subview.
- `MBHSharing`: plain plus `button.window.sharingType = .readOnly`.
- `MBHShot`: both features, plus the ` CLI` button title.
- `MBHSwift`: AppKit item created by a delegate under SwiftUI `App`; an
  uninserted `MenuBarExtra` supplies its scene, as in DuoPaste.
- `MBHSwiftShot`: SwiftUI lifecycle with the same extra features as `MBHShot`.
- `MBHExtra`: SwiftUI `MenuBarExtra(.window)`, as in DuoSub.

Additional controlled launch arguments used during investigation:
`--sharing-first`, `--drop-first`, `--cycle-sharing`, `--edit-menu`, and
`--preflight`. They exercise setup order, a capture-sharing transition, a main
Edit menu, and `CGPreflightScreenCaptureAccess()` respectively.

No variant sets `NSStatusItem.isVisible`. Each process writes state to
`$TMPDIR/menu-bar-visibility/<name>.json` every 250 ms and appends launch/KVO
events to `<name>.jsonl`. In these trials, `isVisible` remained true even when
the system hid the icon. It is not the visibility verdict.

## Run the actual switch test

Use Cua Driver to inspect the current System Settings sheet and MenuBarAgent
window. PIDs and window IDs must come from the current session, rather than
the recorded machine-specific values below. Open Menu Bar Controls first.

```sh
cua-driver call list_windows '{"app":"System Settings"}'
cua-driver call list_windows '{"app":"MenuBarAgent"}'
python3 tools/menu-bar-visibility/trial.py MBHShot --rounds 3 \
  --settings-pid 5822 --settings-window 6710 \
  --bar-pid 98449 --bar-window 6777 \
  --output tools/menu-bar-visibility/build/new-trial
```

The script pairs each row's static label with the following checkbox, reads
the switch back, expands overflow, and captures the bar before disabling,
after disabling, and after re-enabling. It restores the initial switch value
in `finally`. It persists only menu-bar AX nodes, excluding unrelated windows.
Always inspect the screenshots: AX may expose a hidden proxy after restarting
MenuBarAgent, and the SwiftUI item may have no searchable app-name label.

For the decisive full-app test, use `ditto` to copy the installed bundle to an
unused test path, verify the files are identical, and launch that exact path
with Cua Driver's `creates_new_application_instance: true`. Keep the original
instance running. With two DuoShot instances, the passing control has two
icons with the switch on and only the original icon with it off; a failing
pair keeps both icons when the switch is off.
Verify the launched PID's executable path, restore the switch, and terminate
only the process created for the trial.
