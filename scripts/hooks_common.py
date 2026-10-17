"""Helpers shared by the Claude and Codex hook installers."""
import json
import os
import shutil
import tempfile

MARKER = "agent-pet-emit"
TIMEOUT = 2
PERMIT_EVENT = "PermissionRequest"
PERMIT_TIMEOUT = 45
BACKUP_SUFFIX = ".bak-agent-pet"


def is_ours(hook):
    return MARKER in hook.get("command", "")


def desired(event, hook_command, permit_command):
    if event == PERMIT_EVENT:
        return permit_command, PERMIT_TIMEOUT
    return hook_command, TIMEOUT


def backup(path):
    if os.path.exists(path) and not os.path.exists(path + BACKUP_SUFFIX):
        shutil.copy2(path, path + BACKUP_SUFFIX)


def write_atomic(path, text):
    """Replace `path` via a temp file in the same directory so a crash never leaves a torn file."""
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o644
    fd, temp = tempfile.mkstemp(dir=directory, prefix=os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(temp, mode)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def dump_json(data):
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def install_into(groups, command, timeout):
    """Put exactly one of our hook objects into `groups`, touching no foreign hook or group."""
    entry = {"type": "command", "command": command, "timeout": timeout}
    placed = False
    emptied = []
    for group in groups:
        hooks = group.get("hooks", [])
        kept = []
        for hook in hooks:
            if not is_ours(hook):
                kept.append(hook)
            elif not placed:
                hook.update(entry)
                kept.append(hook)
                placed = True
        if len(kept) != len(hooks):
            group["hooks"] = kept
            if not kept:
                emptied.append(group)
    groups[:] = [g for g in groups if not any(g is e for e in emptied)]
    if not placed:
        groups.append({"hooks": [entry]})


def remove_from(groups):
    """Drop only our hook objects; groups that become empty because of that go too. Returns True if anything changed."""
    changed = False
    for group in groups:
        hooks = group.get("hooks", [])
        kept = [h for h in hooks if not is_ours(h)]
        if len(kept) != len(hooks):
            group["hooks"] = kept
            changed = True
    if changed:
        groups[:] = [g for g in groups if g.get("hooks")]
    return changed
