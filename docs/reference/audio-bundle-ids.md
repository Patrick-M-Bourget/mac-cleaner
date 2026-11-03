# Audio software bundle IDs (#704)

Checked 2026-11-03 for Decision 151's lists (`PlugInUninstall.hosts`, `VendorTool.known`, `AudioSoftware`). Decision 41: an app is
recognised by its exact bundle ID only, so an ID goes in Core only with a primary source: the app's own Info.plist, the vendor's
own source code or docs, or Apple's first-party data for Apple's apps. Third-party catalogs, crash logs, Homebrew casks and
preference-file names don't count.

## Resolved

| Product | Bundle ID | Executable | Source | How checked |
|---|---|---|---|---|
| Ableton Live (12 Suite) | `com.ableton.live` | `Live` | Info.plist on this Mac | `/Applications/Ableton Live 12 Suite.app` |
| Pro Tools | `com.avid.ProTools` | `Pro Tools` | Info.plist on this Mac | `/Applications/Pro Tools.app` |
| Native Access | `com.native-instruments.nativeaccess2` | `Native Access` | Info.plist on this Mac | `/Applications/Native Access.app` |
| UA Connect | `com.uaudio.ua-connect` | `UA Connect` | Info.plist on this Mac | `/Applications/UA Connect.app` |
| Logic Pro (12.4) | `com.apple.logic10` | — | Apple's App Store lookup API | `https://itunes.apple.com/search?term=logic+pro&entity=macSoftware` (`bundleId`) |
| GarageBand (10.4.14) | `com.apple.garageband10` | — | Apple's App Store lookup API | same, `term=garageband` |
| MainStage (4.3.1) | `com.apple.mainstage3` | — | Apple's App Store lookup API | same, `term=mainstage`: MainStage 4 keeps the 3 ID |
| Ardour 8, Ardour 9 | `org.ardour.Ardour8`, `org.ardour.Ardour9` | `Ardour8`, `Ardour9` | Ardour's build script | `github.com/Ardour/ardour` `tools/osx_packaging/osx_build` at tags 8.12 and 9.8: `--public` sets `BUNDLE_ID_BASE=org.ardour`, `EXECUTABLE=Ardour${major_version}`, and `Info.plist.in` sets `CFBundleIdentifier` to `@IDBASE@.@IDSUFFIX@` (base.executable) |

Also on this Mac, not on any list (Universal Audio's interface tools, not managers or hosts): UAD Console `com.uaudio.console3`,
UAD Meter & Control Panel `com.uaudio.uad-meter`, the UAD uninstaller `com.uaudio.UAD2Uninstaller`.

## Unresolved

No primary source found (vendor docs, release notes and deployment guides searched; none publishes the bundle ID, and the apps
aren't installed here). These stay off the lists, or keep their existing unchecked entry:

- **DAWs:** Cubase, Nuendo, Studio One, Digital Performer, Luna, Renoise, Tracktion Waveform (no ID in Core); Reason, Bitwig Studio,
  FL Studio, REAPER (existing IDs, unchecked); Ableton Live's other editions and older versions (only 12 Suite seen).
- **Vendor tools:** Waves Central, Arturia Software Center, Softube Central (existing IDs, unchecked); iZotope Product Portal, Spitfire
  Audio, Plugin Alliance Installation Manager, Splice, Steinberg Download Assistant and Activation Manager, Avid Link, Output Hub,
  Kontakt standalone (not listed).
- **Doubts about existing unchecked IDs:** third-party catalogs (not sources) show Waves Central as `com.WavesAudio.central` and
  Bitwig Studio as `com.bitwig.studio`, not Core's `com.wavesaudio.wavescentral` and `com.bitwig.BitwigStudio`
  (`com.bitwig.BitwigStudio` is Bitwig's Flathub ID). Check these first on a Mac that has them.
- Vendor docs that name preference files (Native Instruments' `com.native-instruments.Kontakt 8.plist`, Splice's
  `Application Support/com.splice.Splice`) aren't bundle IDs and weren't used.

The quickest way to resolve the rest: read `CFBundleIdentifier` from the app's Info.plist on a Mac that has it installed.

## Drivers: how they name their maker

- **HAL (Core Audio) drivers:** a CFPlugIn bundle with the `.driver` suffix in `/Library/Audio/Plug-Ins/HAL`; the host loads
  factories of type `kAudioServerPlugInTypeUUID` (`443ABAB8-E7B3-491A-B985-BEB9187030DB`) listed under `CFPlugInTypes`
  (SDK header `CoreAudio.framework/Headers/AudioServerPlugIn.h`, MacOSX27.0 SDK). The header names only the system folder;
  `AudioSoftware.drivers` also lists `~/Library/Audio/Plug-Ins/HAL`.
- **MIDI drivers:** CFPlugIns of type `kMIDIDriverTypeID` (`ECDE9574-0FE4-11D4-BB1A-0050E4CEA526`) in `/Library/Audio/MIDI Drivers`
  or `~/Library/Audio/MIDI Drivers` (and, for old drivers, `/System/Library/Extensions`) (`CoreMIDI.framework/Headers/MIDIDriver.h`).
- **Maker:** neither header defines a maker key. The maker is the vendor part of `CFBundleIdentifier` and, when present,
  `NSHumanReadableCopyright`, which is optional: on this Mac `audio.existential.BlackHole2ch` has none,
  `com.avid.ProToolsAudioBridge` has one. The code-signing Team ID would be a stronger tie but isn't read today.
- **Apple's:** bundle ID `com.apple.`; one can sit in `/Library/Audio/Plug-Ins/HAL` (here `com.apple.audio.ParrotAudioPlugin`), so
  the folder alone doesn't say it's a third party's. `AudioSoftware.drivers` already skips `com.apple.` IDs.
- **DriverKit audio extensions (`.dext`):** live inside their app at `Contents/Library/SystemExtensions`; "The system automatically
  uninstalls any system extensions when the user deletes the corresponding app"
  ([Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers);
  [Creating an audio device driver](https://developer.apple.com/documentation/audiodriverkit/creating-an-audio-device-driver)).
  They go with their app, so `AudioSoftware.drivers` needs no change for them.
