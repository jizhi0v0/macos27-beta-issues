# DuoShot system menu-bar switch investigation

> Track / 关注：[GitHub issue #36](https://github.com/jizhi0v0/macos27-beta-issues/issues/36)

Observed on the user's Mac, macOS 27.3 beta 1 / 26C5035r, on 2026-11-12–13.
The user reported that DuoPaste and DuoSub obey the system switch while
DuoShot's switch remains off with its icon still visible.

## Conclusion supported by the controls

The failure follows DuoShot's installation context in this environment. The
installed bundle's files, including the executable, Info.plist, and signature,
work unchanged when copied to the repository's test directory. Fresh instances
from two paths in `/Applications` fail. That locates the observed failure in
system application association/visibility management, rather than requiring a
change from AppKit to SwiftUI or removal of DuoShot's drop target.

The precise private system record responsible is **not identified**. These
trials do not prove that all apps in `/Applications` are affected, nor that the
problem was introduced in this particular beta. No older-OS comparison was run
for this issue.

## Decisive unchanged-bundle sequence

The user's original PID 1096 stayed running throughout. Each additional app
was launched by exact path with Cua Driver 0.47.19 and
`creates_new_application_instance: true`; its actual executable path was
checked. Each round records the real system checkbox as 1 → 0 → 1 and captures
the menu bar with overflow expanded.

1. `untouched-bundle-same-test-path/`: `ditto` copy of the complete installed
   bundle to `tools/menu-bar-visibility/build/FullDuoShot.app`, PID 35554. Three
   rounds: two DuoShot icons on → one off → two on. The original CLI-marked
   icon remains; the copied instance's camera icon disappears. See
   [on](untouched-bundle-same-test-path/DuoShot-baseline.png) and
   [off](untouched-bundle-same-test-path/DuoShot-1-off.png).
2. `original-path-after-copy/`: terminate the test copy, then launch another
   `/Applications/DuoShot.app` instance, PID 36714. Two rounds: two on → two
   off → two on. Both stay visible. See
   [on](original-path-after-copy/DuoShot-baseline.png) and
   [off](original-path-after-copy/DuoShot-1-off.png).
3. `alternate-name-in-applications/`: terminate PID 36714, then launch an
   untouched `ditto` copy at `/Applications/DuoShot Menu Bar Test.app`, PID
   37651. Two rounds: two on → two off → two on. The path was confirmed by
   `ps`; both icons remain in the [off screenshot](alternate-name-in-applications/DuoShot-1-off.png).
   This test bundle was removed after its process exited.
4. `same-name-in-test-directory/`: launch an untouched copy under its original
   basename at `tools/menu-bar-visibility/build/DuoShot.app`, PID 38809. Two
   rounds: two on → one off → two on. See
   [on](same-name-in-test-directory/DuoShot-baseline.png) and
   [off](same-name-in-test-directory/DuoShot-1-off.png).

`bundle-comparison.json` records that all four regular files in both remaining
test copies are byte-identical to the installed bundle. Both executable code
directories have CDHash `9fc8a401747faa0718aa28391c13e725456866f4`; bundle ID is
`com.boli.duoshot`, Team ID `RS59HDH7Y3`. These controls were not re-signed.

Example actual command for step 1 (exit 0, switch restored to 1):

```sh
python3 tools/menu-bar-visibility/trial.py DuoShot --rounds 3 \
  --output baselines/27.3-beta1-26C5035r/menu-bar-visibility/untouched-bundle-same-test-path \
  --settings-window 6710 --bar-pid 98449 --bar-window 6777
```

At the time the script defaulted `--settings-pid` to 5822. The checked-in
version now requires all four process/window arguments explicitly, since
those defaults would be unsafe to reuse in another session. Its saved output
includes the raw switch readbacks and matching menu-bar nodes. Unrelated
window nodes have been removed from the stored AX query results.

## Earlier controls

The root-level `MBH*.jsonl` and PNG files correspond to the seven minimal
implementations documented in [the probe README](../../../tools/menu-bar-visibility/README.md).
All hide and reappear; `MBHShot` was repeated three times. `MBHSDKShot` repeats
the combined variant with SDK 26 linkage. The root MBHExtra screenshots show
the star icon disappearing even though its AX query cannot find the app name.

Additional directories preserve the investigation rather than establish
independent root causes:

- `identity-control/`: combined probe under DuoShot's bundle ID and Developer
  ID identity, three successful rounds.
- `sdk26/`, `old-link-metadata/`, `info-plist/`: older linkage metadata and
  installed bundle metadata did not reproduce failure in the test directory.
- `sharing-cycle/`, `sharing-first/`, `duoshot-order/`, `edit-menu/`,
  `preflight/`: capture-sharing transitions, early window/drop setup, main
  Edit menu, and successful screen-capture preflight still permit hiding.
- `original-before/`: the original installed process fails three rounds.
- `original-recreation/`, `original-after/`, `original-recreated-allowed/`:
  turning off the app's CLI, removing/recreating its status item, and restoring
  the CLI do not cure the system-switch failure.
- `menubaragent-restart/`: MenuBarAgent PID 762 was terminated and relaunched
  as 98449; the original app still fails three rounds.
- `same-binary-new-process/`: a second process from the original path also
  fails, before the decisive copy sequence above.
- `full-rebuild/`: an unmodified current-source rebuild in a copied test
  bundle works. `old-binary-same-path/` then replaces it with the old installed
  executable and also works. The unchanged-bundle sequence above removes the
  rebuild and re-signing confounders from those preliminary observations.
- `misattribution-control/`: a protected ControlCenter preference snapshot
  contained an old DuoShot build path associated with DuoTerminal. Turning
  DuoTerminal's switch off three times did not hide DuoShot. Thus that stale
  entry is **not an established explanation**. The full preference snapshot
  remains in ignored local build output and is not part of this baseline.

After MenuBarAgent restarted, its AX tree sometimes contained application
menu proxies even when icons were hidden. Counts of matching AX nodes and
`NSStatusItem.isVisible` are therefore not sufficient verdicts. The PNGs are
menu-bar-only captures and provide the visibility check. In particular,
several earlier logs contain zero matching names while the screenshots show
the probe icon; this is an AX-label limitation, not a failed launch.

## Restoration

The system DuoShot switch, the app's Show menu bar icon setting, and its Allow
command-line capture setting all read back 1. All test app processes were
terminated. The user's original PID 1096 and editor window 5147 were retained.
The Settings windows and Finder windows opened for this investigation were
closed. No original app bundle, source repository, or system preference file
was edited.
