# PlayStation Remote Play (`emuden.chiaki`)

PlayStation 4 and PlayStation 5 Remote Play in EmuDEN through **Chiaki-NG** (`Denarmo/chiaki-ng`, `ecp` branch), speaking **Emulator Control Protocol (ECP) Level 2** on Android and Desktop.

## Setup

1. Install **Chiaki-NG** when prompted by EmuDEN (downloaded automatically on Windows and Linux; APK prompt on Android).
2. Open Chiaki-NG once directly and register your PlayStation 4 or PlayStation 5 console.
3. Add a `.chiaki` or `.psremote` file per console to your EmuDEN game folder:
   - **Android:** Inside Chiaki-NG, tap the menu button (`⋮`) on a registered console and choose **Save `.chiaki` for EmuDEN**.
   - **Manual file (Desktop or Android):** Create a text/JSON file ending in `.chiaki`, for example `PS5.chiaki`:

```json
{
  "nickname": "PS5-LivingRoom",
  "mac": "01:23:45:67:89:ab",
  "target": "ps5",
  "wakeup": true
}
```

You can also add `"host": "192.168.1.50"` for consoles on another subnet or `"passcode": "0000"` if your PlayStation account requires a login PIN.

## Capabilities & Notes

- PlayStation consoles cannot save/load emulator states or rewind live streams; those features are disabled for `psremote`.
- On **Android**, pause/resume, pause menu hand-over (`menu_chord` or Back), in-game screenshots, performance metrics, volume/mute control, and live/restart settings are supported over ECP Level 2.
- On **Windows** and **Linux**, `chiaki-ecp` discovers and wakes consoles from Rest Mode over DDP before starting `chiaki stream ... --exit-app-on-stream-exit` and supports ECP settings and one-shot inspection.
- Source code and AGPL-3.0-only licensing details for this ECP fork are published at <https://github.com/Denarmo/chiaki-ng/tree/ecp>.
