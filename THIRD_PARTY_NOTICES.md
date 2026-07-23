# MegaWhisper third-party notices

MegaWhisper includes and interoperates with third-party components. The
MegaWhisper proprietary license applies only to MegaWhisper itself. Each
third-party component remains governed by its own license, and those terms take
priority for that component.

The installed application includes the MegaWhisper license and available
third-party license texts under `share/licenses/megawhisper`. In particular,
the statically linked `whisper.cpp` component is distributed under its MIT
license, which is installed under `share/licenses/megawhisper/whisper.cpp`.
The Flatpak installs app-local Qt Multimedia license texts under
`share/licenses/qtmultimedia`. The AppImage keeps its collected package license
texts under `share/licenses/megawhisper/third-party`.

## Optional NVIDIA Parakeet model

MegaWhisper does not bundle model weights in the application packages. If a
user explicitly downloads `Parakeet TDT 0.6B v3 Q8_0` from the model settings,
MegaWhisper retrieves a quantized GGML artifact derived from NVIDIA's
`Parakeet TDT 0.6B v3` model.

- Model and attribution: NVIDIA Corporation, Parakeet TDT 0.6B v3.
- Original model: <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>
- Quantized artifact: <https://huggingface.co/ggml-org/parakeet-GGUF>
- Model license: Creative Commons Attribution 4.0 International,
  <https://creativecommons.org/licenses/by/4.0/>

The optional artifact is a converted and quantized form of the original model;
it is not an unmodified NVIDIA checkpoint. NVIDIA does not endorse
MegaWhisper. The CC BY 4.0 terms apply to the model material independently of
the MegaWhisper application license.

Each MegaWhisper release provides a matching
`MegaWhisper-VERSION-third-party-compliance.tar.zst` bundle. It contains the
binary SBOM, notices, license inventories, and corresponding source materials
required for bundled third-party components. It does not contain MegaWhisper
source code.

Download the compliance bundle for the exact installed version from the
[MegaWhisper releases](https://github.com/DXVSI/MegaWhisper/releases). Keep the
bundle together with any redistributed third-party material where its license
requires that corresponding source or notices remain available.

Questions about MegaWhisper licensing may be submitted through the
[MegaWhisper repository](https://github.com/DXVSI/MegaWhisper).
