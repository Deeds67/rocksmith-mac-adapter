# rocksmith-mac-adapter

Play **Rocksmith 2014 Remastered (native macOS version)** with a regular audio interface, such as a Focusrite Scarlett, instead of the official Real Tone cable. No paid apps needed.

> On Windows, use [RS_ASIO](https://github.com/mdias/rs_asio). It doesn't work on macOS, which is why this exists.

## How it works

On macOS, Rocksmith only accepts an input device named **"Rocksmith USB Guitar Adapter"**. This project provides two pieces:

1. **A virtual audio device** with that name. It's a custom build of [BlackHole](https://github.com/ExistentialAudio/BlackHole) with 2 channels at 48 kHz.
2. **`rocksmith-router`**, a small command-line tool that copies one input of your interface (input 1 by default) into both channels of that device, with very little added delay.

```
Guitar → Scarlett input 1 → rocksmith-router → "Rocksmith USB Guitar Adapter" → Rocksmith
```

### Why not just rename an aggregate device?

The common tip of creating an Aggregate Device in Audio MIDI Setup and naming it "Rocksmith USB Guitar Adapter" exposes **every** channel of your interface to the game. For a Scarlett 4i4, that's 6 inputs, including the two loopback channels that carry the computer's own playback. In practice this caused:

- buzzing and feedback, because the game's audio came back in through loopback
- *"two Rocksmith cables detected, disconnect one"*
- the tuner not detecting the guitar

Giving the game one clean guitar signal fixes all three.

## Requirements

- Mac with macOS (tested on Apple Silicon, macOS 26)
- Xcode (to build the driver) and the Swift toolchain
- Any USB audio interface. Tested with a Scarlett 4i4 (4th gen).

## Install

```sh
git clone https://github.com/Deeds67/rocksmith-mac-adapter.git
cd rocksmith-mac-adapter

# 1. Build the virtual device driver (clones BlackHole and builds it)
./build-driver.sh

# 2. Install it (needs admin password); audio restarts briefly
sudo cp -R build/RocksmithAdapter.driver /Library/Audio/Plug-Ins/HAL/
sudo killall -9 coreaudiod

# 3. Build the router
swiftc -O router.swift -o rocksmith-router
```

Afterwards, **"Rocksmith USB Guitar Adapter"** should appear in Audio MIDI Setup.

> ⚠️ Only one device may carry that name. Delete any aggregate device or Loopback device you named "Rocksmith USB Guitar Adapter" before, or the game will report two cables.

## Play

1. Plug the guitar into **input 1** of your interface. Set the gain so it never peaks red.
2. In **System Settings → Sound → Output**, pick your interface. This is where the game's audio plays.
3. Start the router and keep it running while you play:
   ```sh
   ./rocksmith-router
   ```
   On first run, macOS asks for microphone permission for your terminal. Allow it.
4. Start Rocksmith.

### Options

```sh
./rocksmith-router                 # first device whose name contains "Scarlett", input 1
./rocksmith-router "MiniFuse"      # any interface: pass part of its name (case-insensitive)
./rocksmith-router "Scarlett" 2    # use input 2 instead
```

If no device matches, it prints the list of available devices.

### Recommended `Rocksmith.ini` setting

In the game folder (`~/Library/Application Support/Steam/steamapps/common/Rocksmith2014/Rocksmith.ini`):

```ini
RealToneCableOnly=1
```

This makes the game ignore other inputs, such as webcams and the built-in microphone.

## Start automatically at login (optional)

Create `~/Library/LaunchAgents/com.example.rocksmith-router.plist`. Adjust the path:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.rocksmith-router</string>
  <key>ProgramArguments</key>
  <array><string>/path/to/rocksmith-mac-adapter/rocksmith-router</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

Then run `launchctl load ~/Library/LaunchAgents/com.example.rocksmith-router.plist`. `KeepAlive` restarts the router if the interface is unplugged and plugged back in.

## Troubleshooting

| Problem | Fix |
|---|---|
| "two cables detected" | Another device is also named "Rocksmith USB Guitar Adapter". Remove it. |
| Device doesn't show up | Check that `/Library/Audio/Plug-Ins/HAL/RocksmithAdapter.driver` exists, then run `sudo killall -9 coreaudiod`. If it still doesn't appear, run `sudo xattr -cr` on the driver. |
| Tuner doesn't hear the guitar | Make sure the guitar is in the input the router uses (default: input 1). Check the gain. |
| Distorted or buzzy sound | Input gain is too high, so the signal clips. Turn it down until it stays green. |
| Occasional tiny click | Expected. The interface and the virtual device run on slightly different clocks, and the router corrects for the drift. |
| Constant crackling | Increase the buffer size in `router.swift` (64 → 128 frames) and rebuild. |

## Uninstall

```sh
sudo rm -rf /Library/Audio/Plug-Ins/HAL/RocksmithAdapter.driver
sudo killall -9 coreaudiod
```

## License

MIT (see [LICENSE](LICENSE)). This covers this repo's code only. The BlackHole driver that `build-driver.sh` downloads and builds is GPL-3.0.

## Credits

- Virtual device: [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio (GPL-3.0)
- Inspired by [RS_ASIO](https://github.com/mdias/rs_asio), which solves the same problem on Windows

Rocksmith is a trademark of Ubisoft. This project is not affiliated with Ubisoft, Focusrite or Existential Audio.
