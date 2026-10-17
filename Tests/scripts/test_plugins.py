"""Packaging checks for the plugin manifests and the hook shim."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
CLAUDE_PLUGIN = os.path.join(ROOT, "plugins", "agent-pet-claude")
CODEX_PLUGIN = os.path.join(ROOT, "plugins", "codex-agent-pet")
SHIM = os.path.join(CLAUDE_PLUGIN, "bin", "agent-pet-hook")
CLAUDE_EVENTS = {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                 "PermissionRequest", "Notification", "Stop", "SessionEnd"}


def load(*parts):
    with open(os.path.join(ROOT, *parts)) as f:
        return json.load(f)


class ManifestTests(unittest.TestCase):
    def test_claude_marketplace_lists_the_plugin_directory(self):
        market = load(".claude-plugin", "marketplace.json")
        self.assertEqual(market["name"], "agent-pet")
        source = market["plugins"][0]["source"]
        self.assertTrue(os.path.isfile(os.path.join(ROOT, source, ".claude-plugin", "plugin.json")))

    def test_claude_hooks_cover_every_event_and_permit_uses_a_longer_timeout(self):
        hooks = load("plugins", "agent-pet-claude", "hooks", "hooks.json")["hooks"]
        self.assertEqual(set(hooks), CLAUDE_EVENTS)
        permit = hooks["PermissionRequest"][0]["hooks"][0]
        self.assertIn("permit --agent claude", permit["command"])
        self.assertEqual(permit["timeout"], 45)
        for event, groups in hooks.items():
            self.assertIn("${CLAUDE_PLUGIN_ROOT}/bin/agent-pet-hook", groups[0]["hooks"][0]["command"], event)

    def test_codex_plugin_points_at_its_hooks_file(self):
        manifest = load("plugins", "codex-agent-pet", ".codex-plugin", "plugin.json")
        self.assertEqual(manifest["hooks"], "./hooks.json")
        hooks = load("plugins", "codex-agent-pet", "hooks.json")["hooks"]
        self.assertIn("permit --agent codex", hooks["PermissionRequest"][0]["hooks"][0]["command"])
        self.assertEqual(hooks["PermissionRequest"][0]["hooks"][0]["timeout"], 45)

    def test_codex_marketplace_lists_the_plugin_directory(self):
        market = load(".agents", "plugins", "marketplace.json")
        path = market["plugins"][0]["source"]["path"]
        self.assertTrue(os.path.isfile(os.path.join(ROOT, path, ".codex-plugin", "plugin.json")))

    def test_dsh_package_declares_a_patch_and_client(self):
        package = load("plugins", "dsh-agent-pet", "package.json")
        self.assertEqual(package["dsh"]["bundle"]["patch"], "./cordis.patch.yml")
        self.assertEqual(package["dsh"]["client"]["platform"], "web")


class ShimTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def run_shim(self, payload):
        return subprocess.run([SHIM, "hook", "--agent", "x"], input=payload, text=True, capture_output=True,
                              env={"HOME": self.home, "PATH": "/usr/bin:/bin"})

    def test_shims_are_executable_copies(self):
        for path in (SHIM, os.path.join(CODEX_PLUGIN, "bin", "agent-pet-hook")):
            self.assertTrue(os.access(path, os.X_OK), path)
        with open(SHIM) as a, open(os.path.join(CODEX_PLUGIN, "bin", "agent-pet-hook")) as b:
            self.assertEqual(a.read(), b.read())

    def test_without_an_installed_emitter_it_is_silent_and_succeeds(self):
        result = self.run_shim("{}")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_with_an_emitter_it_forwards_arguments_and_stdin(self):
        emit_dir = os.path.join(self.home, ".local", "agent-pet")
        os.makedirs(emit_dir)
        emit = os.path.join(emit_dir, "agent-pet-emit")
        with open(emit, "w") as f:
            f.write('#!/bin/sh\necho "args:$*"\ncat\n')
        os.chmod(emit, 0o755)
        result = self.run_shim("payload")
        self.assertEqual(result.stdout, "args:hook --agent x\npayload")


if __name__ == "__main__":
    unittest.main()
