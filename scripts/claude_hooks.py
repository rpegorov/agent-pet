#!/usr/bin/env python3
"""Install or remove agent-pet hooks in ~/.claude/settings.json."""
import json
import os
import sys

import hooks_common as common

EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
          "PermissionRequest", "Notification", "Stop", "SessionEnd"]
HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".claude")
SETTINGS = os.path.join(CONFIG_DIR, "settings.json")


def load():
    if not os.path.exists(SETTINGS):
        return {}
    with open(SETTINGS) as f:
        return json.load(f)


def save(data):
    common.backup(SETTINGS)
    common.write_atomic(SETTINGS, common.dump_json(data))


def install(hook_command, permit_command):
    if not os.path.isdir(CONFIG_DIR):
        print("claude: ~/.claude not found, skipping hooks")
        return
    data = load()
    hooks = data.setdefault("hooks", {})
    for event in EVENTS:
        command, timeout = common.desired(event, hook_command, permit_command)
        common.install_into(hooks.setdefault(event, []), command, timeout)
    save(data)


def uninstall():
    if not os.path.exists(SETTINGS):
        return
    data = load()
    hooks = data.get("hooks", {})
    changed = False
    for event in list(hooks):
        if common.remove_from(hooks[event]):
            changed = True
            if not hooks[event]:
                del hooks[event]
    if changed:
        save(data)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "install" and len(sys.argv) == 4:
        install(sys.argv[2], sys.argv[3])
    elif action == "uninstall":
        uninstall()
    else:
        sys.exit("usage: claude_hooks.py install <hook-command> <permit-command> | uninstall")


if __name__ == "__main__":
    main()
