#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "Sources/DiscordVoiceHotkeyCore/DefaultShortcut.swift"
HOTKEY = ROOT / "Sources/DiscordVoiceHotkey/HotKey.swift"


def test_control_r_is_the_default_shortcut() -> None:
    assert CORE.exists(), "Default shortcut policy is missing"
    core = CORE.read_text(encoding="utf-8")
    hotkey = HOTKEY.read_text(encoding="utf-8")

    assert "static let keyCode: UInt32 = 15" in core
    assert "static let carbonModifiers: UInt32 = 1 << 12" in core
    assert 'static let displayName = "⌃R"' in core
    assert "keyCode: DefaultShortcut.keyCode" in hotkey
    assert "carbonModifiers: DefaultShortcut.carbonModifiers" in hotkey
    assert "displayName: DefaultShortcut.displayName" in hotkey


if __name__ == "__main__":
    test_control_r_is_the_default_shortcut()
