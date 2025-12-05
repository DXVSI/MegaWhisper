<h1 align="center">🎙️ MegaWhisper</h1>

<p align="center">
  <b>Powerful speech-to-text tool for Linux</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Qt-6.x-green.svg" alt="Qt">
  <img src="https://img.shields.io/badge/Platform-Fedora%20Linux-blue.svg" alt="Platform">
</p>

---

Voice-to-text application for Linux with local Whisper and OpenAI API support.

## Features

- **Local Whisper** — works offline, your data stays on your machine
- **OpenAI API** — cloud transcription via Whisper API
- **Model download** — download models directly from the app
- **System tray** — runs in background with quick access
- **Hotkeys** — start recording with keyboard shortcuts
- **Recording history** — all transcriptions are saved
- **Translation** — built-in translation via GPT

## Installation

### Download

Download the latest version from [Releases](https://github.com/DXVSI/MegaWhisper/releases).

### Run

```bash
chmod +x megawhisper
./megawhisper
```

Application menu shortcut is created automatically on first launch.

## System Requirements

- **OS:** Fedora Linux
- **Desktop:** KDE Plasma, GNOME (Wayland)

### Install dependencies

```bash
sudo dnf install qt6-qtbase portaudio flac
```

## Usage

1. Launch the app — icon appears in system tray
2. Open settings (right-click → Settings)
3. Choose mode: **Local Whisper** or **OpenAI API**
4. For local mode — download a model
5. Press hotkey (default `Ctrl+Shift+Space`) and speak
6. Text appears in active window or clipboard

## Local Whisper Models

| Model | Size | Description |
|-------|------|-------------|
| tiny | ~75 MB | Fastest |
| base | ~142 MB | Fast |
| small | ~466 MB | Balanced |
| medium | ~1.5 GB | Accurate |
| large-v3 | ~3 GB | Latest |

For Russian language, **medium** or **large-v3** recommended.
