# OpenWispr

OpenWispr is a local voice-dictation app for macOS. Press the Globe/Fn key, speak, then press it again; OpenWispr transcribes speech on your Mac and inserts the text at the current cursor.

## Install from this repository

Requirements: macOS 13 or later, Homebrew, and Swift 5.9 or later. The installer installs `whisper-cpp` with Homebrew if needed.

```bash
git clone https://github.com/zhaoyanthu/open-wispr.git
cd open-wispr
./scripts/install-from-source.sh
```

The installer builds the app, places it at `~/Applications/OpenWispr.app`, and starts it automatically when you log in. It does not restart the app after you choose **Quit** from the menu bar. Open it again from the Dock, or log in again, to start it.

On first launch, allow microphone access. Then enable **OpenWispr** under **System Settings → Privacy & Security → Accessibility** so it can detect the global hotkey and insert dictated text. The default `small` model downloads automatically on first launch. Wait for the waveform icon in the menu bar before dictating.

For an existing clone, update and reinstall with:

```bash
git pull --ff-only
./scripts/install-from-source.sh
```

## Use OpenWispr

- The default hotkey is **Globe/Fn**. In toggle mode, press it once to start recording and again to stop and transcribe.
- Fresh installs automatically detect the spoken language. To force a language, set `"language": "en"` or `"language": "zh"` in `~/.config/open-wispr/config.json`, then restart OpenWispr.
- Choose **Hotkey** in the menu bar to select Fn/Globe, Right Option, F5, or Right Command. If Fn is assigned to emoji or input-language switching on your Mac, disable that assignment in Keyboard or your input method settings.
- Choose **Model** to switch Whisper models. Missing models download when selected. The default is `small`, which supports English, Chinese, and other languages.
- Choose **Show Standby Bar** to show or hide the optional translucent bar. Drag it to move it, double-click to reset its position, or hover and click × to hide it.
- Choose **Quit** in the menu bar to keep the app closed for the rest of the current login session. Opening OpenWispr from the Dock starts it again.

OpenWispr starts when you log in. It runs speech recognition locally; model downloads are the only network activity.

## Update and uninstall

Pull the latest changes in the clone, then run `./scripts/install-from-source.sh` again. To stop automatic login startup, remove `~/Library/LaunchAgents/com.human37.open-wispr.plist` and log out and back in. To remove the app, quit OpenWispr and delete `~/Applications/OpenWispr.app`. Your settings and downloaded models are stored separately in `~/.config/open-wispr/` and `~/Library/Application Support/open-wispr/`.

## Build manually

```bash
brew install whisper-cpp
swift build -c release
```

The executable is `.build/release/open-wispr`. To create an app bundle, use `scripts/bundle-app.sh` with the executable path, output path, and version:

```bash
./scripts/bundle-app.sh .build/release/open-wispr OpenWispr.app 0.11.8
```

## License

MIT
