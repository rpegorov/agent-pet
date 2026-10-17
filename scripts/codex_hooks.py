#!/usr/bin/env python3
"""Install or remove agent-pet hooks in ~/.codex/hooks.json and trust them in config.toml.

Codex keys a hook's trust by its position (event, group index, hook index), so any
change that shifts a foreign hook has to move that hook's trust entry with it.
"""
import hashlib
import json
import os
import re
import sys

import hooks_common as common

EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
          "PermissionRequest", "Stop", "SessionEnd"]
HOME = os.path.expanduser("~")
CODEX_DIR = os.path.join(HOME, ".codex")
HOOKS_JSON = os.path.join(CODEX_DIR, "hooks.json")
CONFIG_TOML = os.path.join(CODEX_DIR, "config.toml")


def snake(event):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", event).lower()


def trust_hash(event, group, hook):
    entry = {"async": False, "command": hook["command"], "timeout": hook["timeout"], "type": "command"}
    if hook.get("statusMessage"):
        entry["statusMessage"] = hook["statusMessage"]
    payload = {"event_name": snake(event), "hooks": [entry]}
    if group.get("matcher"):
        payload["matcher"] = group["matcher"]
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(text.encode()).hexdigest()


def state_key(event, group_index, hook_index):
    return f"{HOOKS_JSON}:{snake(event)}:{group_index}:{hook_index}"


def table_header(key):
    return f'[hooks.state."{key}"]'


def table_pattern(key):
    return re.compile(r"\n?" + re.escape(table_header(key)) + r"\n(?:(?!\[).*\n?)*")


def get_trust(config, key):
    match = re.search(re.escape(table_header(key)) + r'\n(?:(?!\[).*\n)*?trusted_hash = "([^"]*)"', config)
    return match.group(1) if match else None


def remove_trust(config, key):
    return table_pattern(key).sub("", config)


def set_trust(config, key, digest):
    if get_trust(config, key) is not None:
        pattern = re.compile(
            r"(" + re.escape(table_header(key)) + r'\n(?:(?!\[).*\n)*?trusted_hash = ")[^"]*"')
        return pattern.sub(lambda m: m.group(1) + digest + '"', config, count=1)
    if config and not config.endswith("\n"):
        config += "\n"
    return config + f'\n{table_header(key)}\ntrusted_hash = "{digest}"\n'


def positions(hooks, event):
    """Map each hook object (by identity) to its trust key."""
    return {id(h): state_key(event, gi, hi)
            for gi, group in enumerate(hooks.get(event, [])) for hi, h in enumerate(group.get("hooks", []))}


def relocate_trust(config, before, after):
    """Move trust entries of surviving hooks to their new keys and drop entries of vanished ones."""
    stale = {key for ident, key in before.items() if after.get(ident) != key}
    saved = {ident: get_trust(config, key) for ident, key in before.items() if after.get(ident) not in (None, key)}
    for key in stale:
        config = remove_trust(config, key)
    for ident, digest in saved.items():
        if digest:
            config = set_trust(config, after[ident], digest)
    return config


def load_hooks():
    if not os.path.exists(HOOKS_JSON):
        return {"hooks": {}}
    with open(HOOKS_JSON) as f:
        return json.load(f)


def read_config():
    if not os.path.exists(CONFIG_TOML):
        return ""
    with open(CONFIG_TOML) as f:
        return f.read()


def save(data, config):
    common.backup(HOOKS_JSON)
    common.backup(CONFIG_TOML)
    common.write_atomic(HOOKS_JSON, common.dump_json(data))
    common.write_atomic(CONFIG_TOML, config)


def install(hook_command, permit_command):
    if not os.path.isdir(CODEX_DIR):
        print("codex: ~/.codex not found, skipping hooks")
        return
    data = load_hooks()
    hooks = data.setdefault("hooks", {})
    config = read_config()
    for event in EVENTS:
        command, timeout = common.desired(event, hook_command, permit_command)
        groups = hooks.setdefault(event, [])
        before = positions(hooks, event)
        common.install_into(groups, command, timeout)
        config = relocate_trust(config, before, positions(hooks, event))
        for gi, group in enumerate(groups):
            for hi, hook in enumerate(group["hooks"]):
                if common.is_ours(hook):
                    config = set_trust(config, state_key(event, gi, hi), trust_hash(event, group, hook))
    save(data, config)


def uninstall():
    if not os.path.exists(HOOKS_JSON):
        return
    data = load_hooks()
    hooks = data.get("hooks", {})
    config = read_config()
    changed = False
    for event in list(hooks):
        before = positions(hooks, event)
        if common.remove_from(hooks[event]):
            changed = True
            config = relocate_trust(config, before, positions(hooks, event))
            if not hooks[event]:
                del hooks[event]
    if changed:
        save(data, config.rstrip("\n") + "\n" if config.strip() else "")


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "install" and len(sys.argv) == 4:
        install(sys.argv[2], sys.argv[3])
    elif action == "uninstall":
        uninstall()
    else:
        sys.exit("usage: codex_hooks.py install <hook-command> <permit-command> | uninstall")


if __name__ == "__main__":
    main()
