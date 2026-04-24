## Ch4ttr

Native macOS dictation app (SwiftUI + AVFoundation + Speech + local Whisper).

## Export a Whisper encoder to Core ML (whisper.cpp)

`whisper.cpp` can run the **encoder** on the Apple Neural Engine (ANE) via Core ML. It generates a compiled Core ML bundle (`.mlmodelc`) that `whisper.cpp` loads at runtime.

### Prereqs

- Xcode installed, and command line tools installed:

```bash
xcode-select --install
```

- Python 3.11 recommended (Sonoma 14+ recommended).

### Generate the Core ML model (example: `base.en`)

From a checkout of `whisper.cpp`:

```bash
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

python3 -m venv .venv
source .venv/bin/activate

pip install ane_transformers openai-whisper coremltools

./models/generate-coreml-model.sh base.en
```

This generates:

- `models/ggml-base.en-encoder.mlmodelc`

### Build `whisper.cpp` with Core ML support

```bash
cmake -B build -DWHISPER_COREML=1
cmake --build build -j --config Release
```

### Using it in Ch4ttr

Ch4ttr runs a bundled `whisper-cpp` sidecar binary. Once that binary is built with `WHISPER_COREML=1` **and** the matching `.mlmodelc` exists next to your `.bin` model (same naming convention as above), the sidecar will load it automatically.

If you want this to be fully bundled inside the app, the `whisper-cpp` executable should be embedded via Xcode:

- Target → Build Phases → **Copy Files** (Destination: **Executables**) → add `whisper-cpp`

# Ch4ttr
