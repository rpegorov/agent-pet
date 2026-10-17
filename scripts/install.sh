#!/usr/bin/env bash
# Install or remove agent-pet: binaries, Claude/Codex hooks, optional LaunchAgent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.local/agent-pet"
BIN_LINK="$HOME/.local/bin/agent-pet-emit"
EMIT="$INSTALL_DIR/agent-pet-emit"
DATA_DIR="$HOME/.agent-pet"
RESOURCE_BUNDLE_GLOB="*_AgentPet.bundle"
LABEL="io.github.rpegorov.agent-pet"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

uninstall=0
launch_agent=0
claude_hooks=1
codex_hooks=1
for arg in "$@"; do
    case "$arg" in
        --uninstall) uninstall=1 ;;
        --launch-agent) launch_agent=1 ;;
        --no-claude-hooks) claude_hooks=0 ;;
        --no-codex-hooks) codex_hooks=0 ;;
        *) echo "usage: install.sh [--uninstall] [--launch-agent] [--no-claude-hooks] [--no-codex-hooks]" >&2; exit 2 ;;
    esac
done

remove_launch_agent() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
}

# Sessions that started before the uninstall still run the old hook command; a no-op keeps it from failing with 127.
write_stub() {
    mkdir -p "$(dirname "$1")"
    rm -f "$1"
    printf '#!/bin/sh\nexit 0\n' > "$1"
    chmod 755 "$1"
}

if [ "$uninstall" = 1 ]; then
    remove_launch_agent
    pkill -x AgentPet || true
    python3 "$ROOT/scripts/claude_hooks.py" uninstall
    python3 "$ROOT/scripts/codex_hooks.py" uninstall
    rm -rf "$INSTALL_DIR"
    write_stub "$EMIT"
    write_stub "$BIN_LINK"
    echo "agent-pet uninstalled; no-op stubs remain at $EMIT and $BIN_LINK so open sessions keep working."
    echo "Restart open Claude/Codex sessions to drop the old hooks, then delete the stubs."
    exit 0
fi

(cd "$ROOT" && swift build -c release)
BUILD_DIR="$(cd "$ROOT" && swift build -c release --show-bin-path)"

mkdir -p "$INSTALL_DIR" "$(dirname "$BIN_LINK")" "$DATA_DIR"
# The log holds tool names and working directories: owner-only, including files from earlier installs.
chmod 700 "$DATA_DIR"
chmod 600 "$DATA_DIR"/events.jsonl* 2>/dev/null || true

was_running=0
if pgrep -x AgentPet >/dev/null; then
    was_running=1
    pkill -x AgentPet || true
fi

# Replace files via rename so each gets a new inode; overwriting in place invalidates the kernel's cached code signature.
install_file() {
    cp "$1" "$2.new"
    mv -f "$2.new" "$2"
}

install_file "$BUILD_DIR/agent-pet-emit" "$EMIT"
install_file "$BUILD_DIR/AgentPet" "$INSTALL_DIR/AgentPet"
# SwiftPM's generated Bundle.module accessor looks for the bundle next to the executable.
for bundle in "$BUILD_DIR"/$RESOURCE_BUNDLE_GLOB; do
    target="$INSTALL_DIR/$(basename "$bundle")"
    rm -rf "$target.new"
    cp -R "$bundle" "$target.new"
    rm -rf "$target"
    mv "$target.new" "$target"
done
rm -f "$BIN_LINK"
ln -s "$EMIT" "$BIN_LINK"

quoted_emit="$(python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$EMIT")"
# Skipped when the agent's plugin carries the hooks: both together would ask every permission twice.
if [ "$claude_hooks" = 1 ]; then
    python3 "$ROOT/scripts/claude_hooks.py" install "$quoted_emit hook --agent claude" "$quoted_emit permit --agent claude"
fi
if [ "$codex_hooks" = 1 ]; then
    python3 "$ROOT/scripts/codex_hooks.py" install "$quoted_emit hook --agent codex" "$quoted_emit permit --agent codex"
fi

if [ "$launch_agent" = 1 ]; then
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$INSTALL_DIR/AgentPet</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST_EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi

if [ "$was_running" = 1 ] && [ "$launch_agent" = 0 ]; then
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        launchctl kickstart -k "gui/$(id -u)/$LABEL"
    else
        nohup "$INSTALL_DIR/AgentPet" >/dev/null 2>&1 &
    fi
fi

echo "agent-pet installed to $INSTALL_DIR"
