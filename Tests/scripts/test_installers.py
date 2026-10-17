"""Tests for the hook installers; run with: python3 -m unittest discover -s Tests/scripts"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts")
HOOK = "/opt/agent-pet/agent-pet-emit hook --agent x"
PERMIT = "/opt/agent-pet/agent-pet-emit permit --agent x"
USER_HOOK = {"type": "command", "command": "/usr/local/bin/user-hook", "timeout": 5}


class InstallerCase(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        os.makedirs(os.path.join(self.home, ".claude"))
        os.makedirs(os.path.join(self.home, ".codex"))

    def run_script(self, name, *args):
        env = dict(os.environ, HOME=self.home)
        return subprocess.run([sys.executable, os.path.join(SCRIPTS, name), *args],
                              env=env, check=True, capture_output=True, text=True).stdout

    def path(self, *parts):
        return os.path.join(self.home, *parts)

    def read_json(self, *parts):
        with open(self.path(*parts)) as f:
            return json.load(f)

    def write_json(self, data, *parts):
        with open(self.path(*parts), "w") as f:
            json.dump(data, f)

    def read_text(self, *parts):
        with open(self.path(*parts)) as f:
            return f.read()

    @staticmethod
    def ours(hooks):
        return [h for groups in hooks.values() for g in groups for h in g["hooks"] if "agent-pet-emit" in h["command"]]


class ClaudeHooksTests(InstallerCase):
    def install(self):
        self.run_script("claude_hooks.py", "install", HOOK, PERMIT)

    def test_install_twice_changes_nothing_and_uses_permit_for_permissions(self):
        self.install()
        first = self.read_text(".claude", "settings.json")
        self.install()
        self.assertEqual(first, self.read_text(".claude", "settings.json"))
        hooks = self.read_json(".claude", "settings.json")["hooks"]
        self.assertEqual(len(self.ours(hooks)), 8)
        permission = hooks["PermissionRequest"][0]["hooks"][0]
        self.assertEqual((permission["command"], permission["timeout"]), (PERMIT, 45))

    def test_old_permission_entry_is_replaced_not_duplicated(self):
        old = {"type": "command", "command": "/opt/agent-pet/agent-pet-emit hook --agent x", "timeout": 2}
        self.write_json({"hooks": {"PermissionRequest": [{"hooks": [old]}]}}, ".claude", "settings.json")
        self.install()
        groups = self.read_json(".claude", "settings.json")["hooks"]["PermissionRequest"]
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["hooks"][0]["command"], PERMIT)

    def test_foreign_hook_sharing_a_group_survives_uninstall(self):
        shared = {"matcher": "Bash", "hooks": [USER_HOOK, {"type": "command", "command": HOOK, "timeout": 2}]}
        self.write_json({"hooks": {"Stop": [shared]}}, ".claude", "settings.json")
        self.install()
        self.run_script("claude_hooks.py", "uninstall")
        hooks = self.read_json(".claude", "settings.json")["hooks"]
        self.assertEqual(hooks["Stop"], [{"matcher": "Bash", "hooks": [USER_HOOK]}])
        self.assertEqual(self.ours(hooks), [])

    def test_preexisting_empty_event_list_is_kept(self):
        self.write_json({"hooks": {"SubagentStop": []}}, ".claude", "settings.json")
        self.install()
        self.run_script("claude_hooks.py", "uninstall")
        self.assertEqual(self.read_json(".claude", "settings.json")["hooks"], {"SubagentStop": []})

    def test_uninstall_without_settings_creates_nothing(self):
        self.run_script("claude_hooks.py", "uninstall")
        self.assertFalse(os.path.exists(self.path(".claude", "settings.json")))

    def test_no_temporary_files_are_left_behind(self):
        self.install()
        self.assertEqual(sorted(os.listdir(self.path(".claude"))), ["settings.json"])

    def test_missing_claude_directory_is_skipped(self):
        os.rmdir(self.path(".claude"))
        self.install()
        self.assertFalse(os.path.exists(self.path(".claude")))


class CodexHooksTests(InstallerCase):
    def install(self):
        self.run_script("codex_hooks.py", "install", HOOK, PERMIT)

    def trust_keys(self):
        return re.findall(r'\[hooks\.state\."([^"]+)"\]', self.read_text(".codex", "config.toml"))

    def key(self, event, group, hook=0):
        return f"{self.path('.codex', 'hooks.json')}:{event}:{group}:{hook}"

    def test_install_is_idempotent_and_trusts_every_hook(self):
        self.install()
        first = (self.read_text(".codex", "hooks.json"), self.read_text(".codex", "config.toml"))
        self.install()
        self.assertEqual(first, (self.read_text(".codex", "hooks.json"), self.read_text(".codex", "config.toml")))
        self.assertEqual(len(self.trust_keys()), 7)

    def test_uninstall_moves_trust_of_a_group_that_followed_ours(self):
        user_group = {"hooks": [USER_HOOK]}
        self.write_json({"hooks": {"Stop": [user_group]}}, ".codex", "hooks.json")
        # The user's group is trusted at index 0; ours is appended after it, then the user adds one more after ours.
        self.install()
        data = self.read_json(".codex", "hooks.json")
        later = {"hooks": [{"type": "command", "command": "/usr/local/bin/later", "timeout": 3}]}
        data["hooks"]["Stop"].append(later)
        self.write_json(data, ".codex", "hooks.json")
        with open(self.path(".codex", "config.toml"), "a") as f:
            f.write(f'\n[hooks.state."{self.key("stop", 2)}"]\ntrusted_hash = "sha256:later"\n')
        self.run_script("codex_hooks.py", "uninstall")
        hooks = self.read_json(".codex", "hooks.json")["hooks"]
        self.assertEqual(hooks["Stop"], [user_group, later])
        config = self.read_text(".codex", "config.toml")
        self.assertIn(f'[hooks.state."{self.key("stop", 1)}"]\ntrusted_hash = "sha256:later"', config)
        self.assertNotIn(self.key("stop", 2), config)
        self.assertEqual(self.ours(hooks), [])
        self.assertEqual(self.trust_keys(), [self.key("stop", 1)])

    def test_uninstall_removes_only_our_trust_entries(self):
        self.install()
        self.run_script("codex_hooks.py", "uninstall")
        self.assertEqual(self.trust_keys(), [])
        self.assertEqual(self.read_json(".codex", "hooks.json")["hooks"], {})

    def test_missing_codex_directory_is_skipped(self):
        os.rmdir(self.path(".codex"))
        self.install()
        self.assertFalse(os.path.exists(self.path(".codex")))


class TimeoutContractTests(unittest.TestCase):
    def test_permit_wait_ends_before_the_hook_timeout(self):
        sys.path.insert(0, SCRIPTS)
        import hooks_common
        source = os.path.join(SCRIPTS, "..", "Sources", "agent-pet-emit", "PermitCommand.swift")
        with open(source) as f:
            match = re.search(r"maxWaitSeconds: TimeInterval = (\d+)", f.read())
        self.assertIsNotNone(match)
        self.assertLess(int(match.group(1)), hooks_common.PERMIT_TIMEOUT)


if __name__ == "__main__":
    unittest.main()
