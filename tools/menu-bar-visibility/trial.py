#!/usr/bin/env python3
"""Exercise a live probe's real System Settings switch through Cua Driver."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("name")
parser.add_argument("--probe-name", help="Probe mode when testing an existing app's bundle identity")
parser.add_argument("--rounds", type=int, default=3)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--settings-pid", type=int, required=True)
parser.add_argument("--settings-window", type=int, required=True)
parser.add_argument("--bar-pid", type=int, required=True)
parser.add_argument("--bar-window", type=int, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
session = "menubar-validation"


def call(tool, **kwargs):
    result = subprocess.run(
        ["cua-driver", "call", tool],
        input=json.dumps({"session": session, **kwargs}),
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def switch():
    for attempt in range(3):
        state = call("get_window_state", pid=args.settings_pid, window_id=args.settings_window,
                     tree_format="both", max_elements=1500, max_depth=4,
                     timeout_ms=10000, include_screenshot=False)
        # The static label PRECEDES its checkbox. Check this pairing against the visible row.
        match = re.search(r'AXStaticText = "' + re.escape(args.name) + r'"\n\s*- \[(\d+)\] AXCheckBox',
                          state["tree_markdown"])
        if match:
            break
        if state.get("degraded") or state.get("truncated"):
            # Cua Driver explicitly recommends foreground on AXCannotComplete.
            call("bring_to_front", pid=args.settings_pid, window_id=args.settings_window)
            continue
        if not state.get("truncated"):
            raise RuntimeError(f"No unambiguous switch for {args.name}")
    else:
        raise RuntimeError(f"Settings AX reads timed out for {args.name}")
    index = int(match[1])
    element = next(e for e in state["elements"] if e["element_index"] == index)
    if element["role"] != "AXCheckBox" or element.get("subrole") != "AXSwitch":
        raise RuntimeError("Matched row is not a switch")
    return element


def menu_elements(elements):
    # The agent's AX tree can also contain other apps' windows after a restart.
    # Persist only top menu-bar nodes; screenshots remain the visual ground truth.
    return [e for e in elements
            if e.get("role") in ("AXMenuBar", "AXMenuBarItem", "AXButton")
            and 0 <= e.get("frame", {}).get("y", -1) < 35]


def record(stage, expected):
    control = switch()
    if control["value"] != str(expected):
        raise RuntimeError(f"{stage}: switch reads {control['value']}, expected {expected}")
    def bar_tree(query):
        return call("get_window_state", pid=args.bar_pid, window_id=args.bar_window,
                    query=query, max_depth=4, max_elements=2000, timeout_ms=3000,
                    tree_format="elements", include_screenshot=False)

    overflow = bar_tree("overflow")
    controls = [e for e in overflow.get("elements", []) if e.get("role") == "AXButton"]
    if len(controls) != 1:
        raise RuntimeError("Cannot independently identify the menu-bar overflow control")
    if controls[0].get("label") == "Show Hidden Menu Bar Items":
        call("click", element_token=controls[0]["element_token"])
        time.sleep(0.4)
    overflow = bar_tree("overflow")
    if not any(e.get("label") == "Hide Menu Bar Items" for e in overflow.get("elements", [])):
        raise RuntimeError("Overflow is not expanded; absence could otherwise mean overflow")
    probe_name = args.probe_name or args.name
    matching = bar_tree(probe_name)
    switch_name_matching = matching if probe_name == args.name else bar_tree(args.name)
    image_path = (args.output / f"{args.name}-{stage}.png").resolve()
    bar = call("get_window_state", pid=args.bar_pid, window_id=args.bar_window,
               include_accessibility_tree=False, screenshot_out_file=str(image_path),
               max_image_dimension=3456)
    probe_path = Path(os.environ.get("TMPDIR", "/tmp")) / "menu-bar-visibility" / f"{probe_name}.json"
    probe = json.loads(probe_path.read_text()) if probe_path.exists() else None
    row = {"stage": stage, "wall_time": time.time(), "switch_name": args.name, "probe_name": probe_name, "switch": control,
           "probe": probe, "menu_bar_image": image_path.name,
           "menu_bar_window": args.bar_window, "menu_bar_bounds": bar.get("window_bounds"),
           "overflow_expanded": True,
           "matching_menu_bar_elements": menu_elements(matching.get("elements", [])),
           "switch_name_menu_bar_elements": menu_elements(switch_name_matching.get("elements", []))}
    with (args.output / f"{args.name}.jsonl").open("a") as log:
        log.write(json.dumps(row, sort_keys=True) + "\n")
    status_elements = [e for e in matching.get("elements", [])
                       if e.get("role") in ("AXButton", "AXMenuBarItem")
                       and 0 <= e.get("frame", {}).get("y", -1) < 35]
    print(json.dumps({"stage": stage, "switch": control["value"],
                      "probe_visible": probe and probe.get("isVisible"),
                      "menu_bar_elements": len(status_elements),
                      "image": image_path.name}), flush=True)


original = switch()
original_value = original["value"]
print(json.dumps({"name": args.name, "original_switch": original}), flush=True)
try:
    if original_value != "1":
        call("click", element_token=original["element_token"])
        time.sleep(1)
    record("baseline", 1)
    for trial in range(1, args.rounds + 1):
        control = switch()
        assert control["value"] == "1"
        call("click", element_token=control["element_token"])
        time.sleep(1)
        record(f"{trial}-off", 0)
        control = switch()
        call("click", element_token=control["element_token"])
        time.sleep(1)
        record(f"{trial}-on", 1)
finally:
    current = switch()
    if current["value"] != original_value:
        call("click", element_token=current["element_token"])
        time.sleep(1)
    restored = switch()
    if restored["value"] != original_value:
        raise RuntimeError("Original switch was not restored")
    print(json.dumps({"restored_switch": restored["value"]}), flush=True)
