# Install OpenWispr from source

This guide installs the version in the `zhaoyanthu/open-wispr` repository. It builds the macOS app locally instead of installing the upstream Homebrew release.

## Requirements

- macOS 13 or later
- Homebrew
- Swift 5.9 or later (install Xcode Command Line Tools with `xcode-select --install` if `swift` is unavailable)

## Install

```bash
git clone https://github.com/zhaoyanthu/open-wispr.git
cd open-wispr
./scripts/install-from-source.sh
```

The script installs `whisper-cpp` if needed, builds OpenWispr, copies the app to `~/Applications/OpenWispr.app`, and registers a login item. OpenWispr launches when you log in. Choosing **Quit** from its menu bar menu keeps it closed until you open it from the Dock or log in again.

## Grant macOS permissions

OpenWispr needs microphone access to record speech and Accessibility access to detect the hotkey and insert text.

1. Allow microphone access when macOS asks.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Turn on **OpenWispr**. If it is missing, click **+**, choose `~/Applications/OpenWispr.app`, and enable it.
4. Wait for the OpenWispr menu bar icon to show the waveform and for setup to finish. The default `small` model downloads automatically on first launch.

If OpenWispr remains on its lock icon, quit and reopen the app after enabling Accessibility. Check the log at `~/Library/Logs/OpenWispr/app.log` for the permission and startup status.

## Use

The default hotkey is Globe/Fn. In toggle mode, press it once to start recording and again to stop and transcribe. Fresh installs automatically detect the spoken language. To force English or Chinese, set `"language": "en"` or `"language": "zh"` in `~/.config/open-wispr/config.json`, then restart OpenWispr. Use the menu bar **Hotkey** submenu to choose Fn/Globe, Right Option, F5, or Right Command. If another app or input method uses Fn, remove that assignment so OpenWispr can receive it.

Use **Model** to choose a Whisper model. The default is `small`; the app downloads other selected models as needed. Use **Show Standby Bar** to toggle the optional floating indicator. You can drag it, double-click to reset it, or hover and click × to hide it.

## Update

In the cloned repository:

```bash
git pull --ff-only
./scripts/install-from-source.sh
```

## Uninstall

Quit OpenWispr, then remove its login item and app:

```bash
launchctl bootout "gui/$(id -u)/com.human37.open-wispr" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.human37.open-wispr.plist"
rm -rf "$HOME/Applications/OpenWispr.app"
```

These commands keep your configuration and downloaded models. They are stored in `~/.config/open-wispr/` and `~/Library/Application Support/open-wispr/`.
