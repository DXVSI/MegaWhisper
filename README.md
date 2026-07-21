# MegaWhisper

Author: [DXVSI](https://github.com/DXVSI)

MegaWhisper is a proprietary Linux desktop application for local and OpenAI-compatible speech transcription. It records through Qt Multimedia, runs local inference through `whisper.cpp`, and keeps output delivery explicit.

## Features

- Local offline transcription with verified GGML models
- Vulkan acceleration with an automatic CPU fallback
- OpenAI-compatible file transcription
- Dictation, long-note, and cloud meeting modes
- Speaker-labelled segments with supported diarization models
- Editable raw, translated, and user-created result variants
- Private SQLite history with configurable audio retention
- Global Shortcuts portal support in Flatpak and AppImage packages
- Clipboard-first output with explicit confirmation or automatic insertion modes
- Russian and English user interfaces

MegaWhisper does not require root, direct input-device access, udev rules, membership in the `input` group, or a privileged input daemon.

## Installation

Flatpak is the recommended package. Install the signed reference from the latest release:

```fish
flatpak install -y --user https://dxvsi.github.io/MegaWhisper/io.github.dxvsi.megawhisper.flatpakref
flatpak run io.github.dxvsi.megawhisper
```

The latest release also provides a portable x86_64 AppImage. Download it from the [latest release](https://github.com/DXVSI/MegaWhisper/releases/latest), then run:

```fish
chmod +x ./MegaWhisper-2.1.1-x86_64.AppImage
./MegaWhisper-2.1.1-x86_64.AppImage --install-desktop-integration
./MegaWhisper-2.1.1-x86_64.AppImage --check-desktop-integration
./MegaWhisper-2.1.1-x86_64.AppImage
```

Portable startup and button-driven operation work without installation. Global Shortcuts and system insertion require the explicit per-user desktop integration shown above. Reinstall it after moving the AppImage because the integration verifies its exact path.

See [INSTALL.md](INSTALL.md) for signature verification, updates, rollback, and package diagnostics.

## Privacy

Local mode does not send audio to a network service. Cloud mode displays an explicit disclosure and sends only the selected recording and job parameters to the configured service. API credentials are stored through the protected credential backend and are not written to plaintext settings.

Audio retention is opt-in. Session audio is removed when the application closes. Text-only mode keeps only a bounded temporary retry copy and does not restore it after restart.

## Release verification

MegaWhisper 2.1.0 and later use the `binary-v1` release contract. A release contains exactly ten uploaded assets: AppImage, AppImage zsync metadata, Flatpak bundle, two Flatpak repository descriptors, a third-party compliance bundle, a recovery bundle, the public release key, `SHA256SUMS`, and its detached signature.

The signed checksum list authenticates all eight payload assets. The public workflow verifies exact GitHub asset IDs, sizes and SHA-256 digests, installs the candidate Flatpak, deploys the signed Pages repository, checks the live HTTPS bytes, and only then publishes the draft Release. If the first deployment fails, the signed recovery state exposes an empty Flatpak repository and disables installation instead of publishing an unverified release.

The public `main` branch and release tag contain only distribution documentation, the website, and verification tooling. GitHub-generated source archives therefore do not contain the MegaWhisper application source code.

## Third-party software

MegaWhisper includes third-party components under their own licenses, including Qt, GStreamer and `whisper.cpp`. The release asset `MegaWhisper-VERSION-third-party-compliance.tar.zst` contains binary SBOMs, build provenance, notices, license information, and corresponding source required for bundled third-party components. It does not contain the MegaWhisper application source code.

See [Third-party notices](THIRD_PARTY_NOTICES.md) for the canonical notice summary.

## License

MegaWhisper 2.1.0 and later are proprietary software. Installation and use of official, unmodified binaries are permitted under the terms in [LICENSE](LICENSE). No right to the application source code, modification, redistribution, or sublicensing is granted.

Third-party components remain governed by their respective licenses.
