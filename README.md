# MegaWhisper

Author: [DXVSI](https://github.com/DXVSI)

MegaWhisper is a Linux desktop application for local and OpenAI-powered speech transcription. It records through Qt Multimedia, runs local inference through `whisper.cpp`, and keeps output delivery explicit and auditable.

## Features

- Local offline transcription with verified, revision-pinned GGML models
- Vulkan acceleration with an automatic CPU fallback
- OpenAI file transcription with bounded, cost-aware retries
- Dictation, long-note, and cloud meeting modes
- Speaker-labelled segments with `gpt-4o-transcribe-diarize`
- Editable raw, translated, and user-created result variants
- Private SQLite history with `session`, `text`, and `audio` retention policies
- Global Shortcuts portal in Flatpak, AppImage, and native builds
- Three explicit output modes: clipboard-only by default, confirmation-based insertion with a second global shortcut, and one automatic insertion attempt immediately after transcription; both beta insertion modes keep the exact text in the clipboard and fail closed
- Russian and English user interfaces

MegaWhisper does not require root, input-device access, udev rules, an `input` group membership, or a privileged input daemon.

## Installation

Flatpak is the primary distribution format for traditional and immutable Linux systems, subject to compatibility with the system's desktop portal implementation. After a stable release is published, download its signed `.flatpakref` from GitHub Release:

```fish
flatpak install -y --user ./io.github.dxvsi.megawhisper.flatpakref
flatpak run io.github.dxvsi.megawhisper
```

The files under `flatpak/*.in` in a source checkout are release-pipeline templates with unresolved repository URL and GPG key placeholders. They cannot be opened, installed, or made valid by renaming. Use the signed `.flatpakref` from a GitHub Release.

The public `main` branch contains the protected distribution workflow and verification files. Complete source snapshots are published as orphan release tags and signed source archives. To build the exact v2.0.0 source tag for the current user, run:

```fish
git clone https://github.com/DXVSI/MegaWhisper.git
cd MegaWhisper
git checkout v2.0.0
scripts/install-local-flatpak.sh 2.0.0
flatpak run io.github.dxvsi.megawhisper.Devel
```

The installer uses an isolated temporary Flatpak build environment and the separate `io.github.dxvsi.megawhisper.Devel` app ID, so it does not replace a stable installation.

After publication, the release also provides a portable AppImage:

```fish
chmod +x ./MegaWhisper-2.0.0-x86_64.AppImage
./MegaWhisper-2.0.0-x86_64.AppImage --install-desktop-integration
./MegaWhisper-2.0.0-x86_64.AppImage --check-desktop-integration
./MegaWhisper-2.0.0-x86_64.AppImage
```

Portable startup and button-driven operation work without installation. Global Shortcuts and system insertion require the explicit per-user desktop integration above. Reinstall it after moving the AppImage because the exact path is verified. `--remove-desktop-integration` removes only files owned by this AppImage integration.

The AppImage uses the Qt GStreamer backend for `QAudioSource` and `QAudioSink`, with its required scanner and plugins. History FLAC is decoded directly through libFLAC without `QMediaPlayer/GstPlay`. Qt FFmpeg and OpenH264 are intentionally excluded. Its license inventory and corresponding-source archives cover bundled libraries, the AppImage runtime, and compiled header-only dependencies including `spirv-headers` and `vulkan-devel`. A clean installation remains clipboard-only. Confirmation-based beta insertion waits for a second global shortcut in the target window. Automatic beta insertion needs no second shortcut and makes exactly one immediate attempt in the window that is active when transcription completes. Both modes keep the text in the clipboard first, require a neutral modifier state, and use Remote Desktop portal with `libei`; the default profile sends `Shift+Insert`. `attempted` records a send attempt, not a proven edit. A denied, revoked, unavailable, busy, or timed-out backend leaves the exact text in the clipboard with no delayed retry. Compatibility with specific target applications remains subject to the manual desktop matrix.

See [INSTALL.md](INSTALL.md) for signature verification, updates, rollback, offline bundle installation, and source builds.

## Privacy

Local mode does not send audio to a network service. Cloud mode displays an explicit disclosure and sends only the selected recording, language, model, and prompt required for that job. The API key is stored through a protected credential backend and is never written to plaintext settings.

Audio retention is opt-in. Session audio is removed when the application closes. Text-only mode keeps only a bounded temporary retry copy and does not restore it after restart.

The provisional local default is the Balanced `whisper-large-v3-turbo-q5_0` profile. It is a runtime convenience, not a quality claim; final model guidance remains gated by real WER/CER, latency, RAM, and VRAM measurements.

## Build and verification

The project uses Qt 6 Widgets, qmake, Qt Multimedia, `whisper.cpp`, SQLite, FLAC, libsamplerate, `libei`, and libxkbcommon. History playback decodes FLAC off the GUI thread, converts canonical PCM to the selected output format, and streams it through `QAudioSink`; stop, replay, device loss, and shutdown do not retain a `GstPlay` worker. The Flatpak ships a full app-local Qt Multimedia 6.11.1 module with the exact upstream QTBUG-147011 fix until the KDE runtime publishes Qt 6.11.2 or newer. Production uses the sandboxed PulseAudio compatibility socket, which is provided by PipeWire Pulse on common modern desktops. CI separately exercises active `QAudioSource` and `QAudioSink` teardown through both that compatibility backend and a temporary direct PipeWire connection, without granting direct PipeWire access to the installed application. CI builds CPU and Vulkan native variants, Flatpak, and an openSUSE-baseline AppImage. Releases include signatures, checksums, SPDX SBOMs, a signed build-provenance document, a public orphan source snapshot without private history, expanded `whisper.cpp` sources, AppImage runtime sources, Qt Multimedia corresponding source, and signed Pages recovery states. The public workflow verifies the candidate website and Flatpak repository locally, including a clean install and smoke test, then publishes one complete Pages tree containing the site and exactly one OSTree state. It verifies the live HTTPS bytes and signed `.flatpakref` before publishing the draft Release. A failed post-deployment check restores the complete previous signed Pages state; the first-release fallback exposes a signed empty repository and disables the install action.

```fish
git checkout v2.0.0
git submodule update --init --recursive
set -x SOURCE_DATE_EPOCH (git log -1 --format=%ct)
scripts/ci/build-native.sh 2.0.0 1 development
env QT_QPA_PLATFORM=offscreen ./run-megawhisper.sh --smoke-test
env QT_QPA_PLATFORM=offscreen ./run-megawhisper.sh --ui-smoke-test
scripts/install-development-desktop.sh install
scripts/install-development-desktop.sh check
```

The native launcher verifies a deterministic content fingerprint and exact package identity, and refuses to run a missing, corrupt, or stale local build. Smoke commands do not require desktop integration. Normal native development startup uses `io.github.dxvsi.megawhisper.NativeDevel`, which is distinct from the `io.github.dxvsi.megawhisper.Devel` Flatpak identity, and requires the explicit integration command above. Rebuilding and installation are always explicit.

The quality runner supports score-only WER/CER reports and real local inference over a separately supplied legal corpus. No private evaluation audio is committed.

## License

MegaWhisper is licensed under GPL-3.0-only. Third-party licenses and corresponding-source artifacts are included with release packages.
