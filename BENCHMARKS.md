# MegaWhisper benchmark reports

These reports contain MegaWhisper measurements for exact model artifacts,
runtime versions, corpus revisions, accelerators, and devices. They are not
general vendor benchmarks and must not be transferred to another quantization,
backend, accelerator, or machine.

Both reports below were measured on 2026-07-22 with Vulkan on an AMD Radeon
RX 7900 XTX using the complete FLEURS `ru_ru/test` split:

- dataset revision:
  `70bb2e84b976b7e960aa89f1c648e09c59f894dd`;
- 775 recordings;
- total audio duration: 8,993,820 ms;
- evaluation manifest SHA-256:
  `79a40044b26d20d0999c8f3b557095d49f1d173b9d022c40caa584fc88ac40e3`;
- text normalization revision: `mw-text-v1`;
- comparability key:
  `fleurs-70bb2e84-ru_ru-test-vulkan-rx7900xtx-balanced-auto`.

FLEURS contains prepared read speech, not live dictation. VRAM and power
consumption were not measured. Process RSS does not include Vulkan memory.
Latency values are comparable only when the complete comparability key
matches.

## mwlab-fleurs-ru-vulkan-2026-07-22-whisper-turbo-q5

- Model ID: `whisper-large-v3-turbo-q5_0`
- Artifact SHA-256:
  `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`
- Backend: `local-whisper`
- Runtime: `whisper.cpp-v1.9.1`

| Metric | Value |
| --- | ---: |
| Normalized WER | 5.5743% |
| Normalized CER | 1.4962% |
| Latency p50 | 217.67 ms |
| Real-time factor p50 | 0.01991 |
| Model preparation | 126.27 ms |
| Process peak RSS | 153.4 MiB |

## mwlab-fleurs-ru-vulkan-2026-07-22-parakeet-q8

- Model ID: `parakeet-tdt-0.6b-v3-q8_0`
- Artifact SHA-256:
  `4d64e9e96c2792186d072fde0034df0ad670cf680a2f53069052ead827fd600e`
- Backend: `local-parakeet`
- Runtime: `parakeet.cpp-v1.9.1`

| Metric | Value |
| --- | ---: |
| Normalized WER | 6.4747% |
| Normalized CER | 1.7068% |
| Latency p50 | 60.60 ms |
| Real-time factor p50 | 0.00545 |
| Model preparation | 579.87 ms |
| Process peak RSS | 127.2 MiB |

## Dataset license

FLEURS is licensed under
[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
Attribution: FLEURS by Alexis Conneau, Min Ma, Simran Khanuja, Yu Zhang, Vera
Axelrod, Siddharth Dalmia, Jason Riesa, Clara Rivera, and Ankur Bapna (2022).
The report uses the pinned public test split without publishing audio in this
source-free distribution repository.
