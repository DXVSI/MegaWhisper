# Installing MegaWhisper

## Choose a package

Flatpak is the recommended format. It isolates the application, captures audio through the PulseAudio compatibility socket, and uses desktop portals for credentials, global shortcuts, and controlled system insertion. MegaWhisper does not receive direct access to `pipewire-0`, input devices, the home directory, or the entire filesystem.

AppImage is intended for systems without a suitable Flatpak runtime. Both formats are available for x86_64 only. Neither requires root access, udev rules, membership in the `input` group, `uinput`, or a privileged input daemon.

## Flatpak

Install the signed `.flatpakref` from the latest stable release:

```fish
flatpak install -y --user https://dxvsi.github.io/MegaWhisper/io.github.dxvsi.megawhisper.flatpakref
flatpak run io.github.dxvsi.megawhisper
```

Installation adds the signed MegaWhisper remote for future updates. KDE runtime 6.11 is downloaded from Flathub when network access is available.

Inspect the granted permissions:

```fish
flatpak info --user --show-permissions io.github.dxvsi.megawhisper
```

Expected permissions include Wayland, fallback X11, the PulseAudio compatibility socket, DRI, and network access. MegaWhisper does not require `filesystem=host`, `filesystem=home`, `devices=all`, direct `pipewire-0` access, or direct access to input devices.

Update, inspect available commits, roll back, or uninstall:

```fish
flatpak update -y --user io.github.dxvsi.megawhisper
flatpak remote-info --user --log megawhisper io.github.dxvsi.megawhisper
flatpak update -y --user --commit=COMMIT io.github.dxvsi.megawhisper
flatpak uninstall -y --user --delete-data io.github.dxvsi.megawhisper
```

Replace `COMMIT` with a value shown by `flatpak remote-info --log`.

### Flatpak bundle

The `MegaWhisper-2.2.0-x86_64.flatpak` file can be installed directly:

```fish
flatpak install -y --user ./MegaWhisper-2.2.0-x86_64.flatpak
```

The bundle contains the URL of the signed update remote. It does not contain the KDE runtime itself, but its `RuntimeRepo` entry allows Flatpak to download the runtime from Flathub. The runtime must be provided separately for a completely offline installation.

## AppImage

Download the AppImage from the [latest release](https://github.com/DXVSI/MegaWhisper/releases/latest), then run:

```fish
chmod +x ./MegaWhisper-2.2.0-x86_64.AppImage
./MegaWhisper-2.2.0-x86_64.AppImage --appimage-updateinformation
env QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.2.0-x86_64.AppImage --smoke-test
./MegaWhisper-2.2.0-x86_64.AppImage --install-desktop-integration
./MegaWhisper-2.2.0-x86_64.AppImage --check-desktop-integration
./MegaWhisper-2.2.0-x86_64.AppImage
```

Button-driven use works without installation. The Global Shortcuts portal and system insertion require explicit desktop integration in the user's XDG directories. Run `--install-desktop-integration` again after moving the AppImage because the desktop entry is bound to its exact absolute path.

Remove the desktop integration files with:

```fish
./MegaWhisper-2.2.0-x86_64.AppImage --remove-desktop-integration
```

If FUSE is unavailable, use:

```fish
env APPIMAGE_EXTRACT_AND_RUN=1 ./MegaWhisper-2.2.0-x86_64.AppImage
```

## Verify release signatures

MegaWhisper 2.1.0 and later use the `binary-v1` contract with exactly ten uploaded assets. Eight payload assets are listed in the signed `SHA256SUMS` file. `SHA256SUMS` and its detached signature cannot be included in that list because doing so would create a circular dependency.

First, obtain the full fingerprint from `RELEASE_KEY_FINGERPRINT` in a trusted checkout of the public distribution repository and compare it with an independent publication by DXVSI. A key downloaded from a Release is not, by itself, a trust source for that same Release.

```fish
set expected (string upper (string trim (cat ./RELEASE_KEY_FINGERPRINT)))
set actual (gpg --batch --with-colons --show-keys ./megawhisper-release-key.asc | awk -F: '$1 == "pub" { primary=1; next } $1 == "fpr" && primary { print toupper($10); exit }')
test "$actual" = "$expected"; or begin; echo "Release key fingerprint does not match" >&2; exit 1; end
gpg --import ./megawhisper-release-key.asc
gpg --verify ./SHA256SUMS.asc ./SHA256SUMS
sha256sum --check ./SHA256SUMS
```

Expected payload assets for v2.2.0:

- `MegaWhisper-2.2.0-x86_64.AppImage`
- `MegaWhisper-2.2.0-x86_64.AppImage.zsync`
- `MegaWhisper-2.2.0-x86_64.flatpak`
- `io.github.dxvsi.megawhisper.flatpakref`
- `io.github.dxvsi.megawhisper.flatpakrepo`
- `MegaWhisper-2.2.0-third-party-compliance.tar.zst`
- `MegaWhisper-2.2.0-recovery.tar.zst`
- `megawhisper-release-key.asc`

## Third-party compliance

`MegaWhisper-2.2.0-third-party-compliance.tar.zst` contains binary SBOMs, build provenance, notices, license inventories, and corresponding source required for bundled third-party components. It does not contain MegaWhisper application source code.

Qt, GStreamer, `whisper.cpp`, the AppImage runtime, and other third-party components remain under their respective licenses. The canonical summary is published in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

MegaWhisper 2.1.0 and later are proprietary software. The terms for installing and using official, unmodified binaries are provided in [LICENSE](LICENSE). The public repository tag contains distribution documentation, the website, and verification tooling, but not the application source code.

## Troubleshooting

### MegaWhisper is already running, but no window or tray icon is visible

Check for a running process:

```fish
flatpak ps | string match -r 'io\.github\.dxvsi\.megawhisper'
```

If the process remained after a desktop session crash, stop only this Flatpak instance and start the application again:

```fish
flatpak kill io.github.dxvsi.megawhisper
flatpak run io.github.dxvsi.megawhisper
```

### The global shortcut is not registered

Check that the desktop portal is running and that the recording shortcut is not already in use. Flatpak and AppImage ask for permission through the system Global Shortcuts portal dialog. Do not add the user to the `input` group or change device permissions.

### Prepared text was not inserted

MegaWhisper first writes the exact result to the clipboard. System insertion is attempted only in the selected output mode and fails closed if the portal denies access, the backend is not ready, another operation is in progress, or a timeout occurs. In that case, the text remains in the clipboard for manual insertion.

### The microphone is not visible

Check the device in the system sound settings, then select it again in MegaWhisper. The application tracks device hotplug events and should not retain a stale device handle.

### A local model does not start

Open Model Manager, repeat model verification, and check available disk space. A model becomes active only after SHA-256 verification and a runtime smoke test. If Vulkan inference fails, MegaWhisper retries inference on the CPU.
