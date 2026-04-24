# Ch4ttr

Native **macOS** dictation helper: record from the microphone, transcribe with your choice of engine, and **paste into the focused app**—with optional **live** streaming text while you speak (Apple Speech).

Think of it as a small, hackable alternative to “big” dictation stacks: SwiftUI UI, local-first options, and clear separation between capture, cleanup, and insertion.

> **License:** This repository does not yet include a top-level `LICENSE` file. Add one before redistributing or packaging releases. The bundled `whisper.cpp` sidecar path is separate; upstream [whisper.cpp](https://github.com/ggml-org/whisper.cpp) has its own license.

---

## Why use Ch4ttr?

- **Privacy paths:** **On-device Apple Speech** (with live insertion into the frontmost field) or **local Whisper** via a bundled `whisper-cpp` sidecar—no cloud required for those modes.
- **Cloud when you want:** **OpenAI** or **Groq** transcription for users who already use those APIs.
- **Actually pastes:** Uses the pasteboard + accessibility-aware text replacement so transcripts land where you are typing (requires **Accessibility** permission).
- **Flexible triggers:** Global **hotkey** (toggle or push-to-talk) plus optional **long-hold modifier** (e.g. hold **Shift alone** for ~2 seconds).
- **Quality-of-life cleanup:** Normalizes spacing, collapses **short repeated phrases** and **long consecutive duplicate clauses** (common when streaming recognition stutters), per-user **dictionary** replacements, and sentence capitalization (where applicable).
- **Voice commands:** Spoken commands to restart / trim paragraph / stop recording (see `VoiceCommandService` in the codebase).
- **Mini recorder:** Compact floating panel with level meter, optional live preview, and quick engine/mic toggles.
- **Profiles:** Local per-user settings and dictionary (no account server in-app).

---

## Requirements

- **Apple Silicon or Intel Mac** with a recent **Xcode** (the project targets a current macOS SDK; check `MACOSX_DEPLOYMENT_TARGET` in `Ch4ttr.xcodeproj` if you need an exact minimum).
- **Microphone** access (prompted at runtime).
- **Speech recognition** access if you use **Apple Speech**.
- **Accessibility** for pasting / live replacement in other apps.
- Optional **Input Monitoring** (macOS may prompt) if you rely on global event taps for modifier monitoring—behavior depends on OS policy.

---

## How to build

1. **Clone**

   ```bash
   git clone <your-repo-url> Ch4ttr
   cd Ch4ttr
   ```

2. **Open in Xcode**

   ```bash
   open Ch4ttr.xcodeproj
   ```

3. **Select the `Ch4ttr` scheme** and **Run** (`⌘R`).

   Command-line build:

   ```bash
   xcodebuild -project Ch4ttr.xcodeproj -scheme Ch4ttr -configuration Debug build
   ```

4. **Whisper sidecar (optional, for Local Whisper)**

   The app expects a `whisper-cpp` executable at `Ch4ttr/Sidecars/whisper-cpp`. A **Run Script** build phase copies it into `Contents/MacOS/whisper-cpp` when present. If the file is missing, the app still builds; **Local Whisper** will not work until you supply a compatible binary.

   Build `whisper.cpp` yourself (see upstream docs), then place the built CLI at that path, or adjust the copy phase in Xcode.

5. **Run tests (optional)**

   ```bash
   xcodebuild -project Ch4ttr.xcodeproj -scheme Ch4ttr -destination 'platform=macOS' test
   ```

---

## First run checklist

1. Launch Ch4ttr, open **Settings** from the menu bar extra or window.
2. Grant **Microphone** and (for Apple Speech) **Speech Recognition**.
3. Enable **Accessibility** so paste / live insertion can target the focused text field.
4. Pick an **engine** (Apple Speech is the default), set **Recording mode** (toggle vs push-to-talk), and record a **hotkey**.
5. Focus a text field in another app and trigger recording—you should see text appear when the session completes (and live updates if using Apple Speech with live insertion).

---

## Engines (what works in code today)

| Engine | Role |
|--------|------|
| **Apple Speech** | On-device **streaming** with **live insertion** when accessibility succeeds; on stop, the app **reuses the live transcript** instead of a second file-based pass when that avoids worse “re-transcription” (see below). |
| **Local Whisper** | Offline batch transcription via `whisper-cpp`; models **Small** / **Medium** download into app support. Optional **Core ML** encoder bundle for ANE (see below). |
| **OpenAI** | Cloud transcription when an API key is set. |
| **Groq** | Cloud transcription when an API key is set. |
| **Anthropic** | Settings placeholder for future “rewrite” style flows; **not** wired as an audio transcription engine (the app surfaces an error if selected for record-transcribe). |
| **Local Model** | Placeholder engine identifier for a future on-device pipeline. |

### Apple Speech: live text vs. a second pass on the WAV

SpeechKit exposes **different** recognition paths for **live audio** (`SFSpeechAudioBufferRecognitionRequest`, what you see while dictating) and **batch audio** (`SFSpeechURLRecognitionRequest` over the saved recording). They can legitimately **diverge**—same mic, same words, different hypotheses (e.g. “some kind of” vs. “sound of”, or drift in longer sentences).

An earlier design ran that **URL pass at every stop** and replaced the whole live-inserted range with its result. In practice that often felt **regressive**: the text looked good while speaking, then **changed for the worse** when the session ended.

**Current behavior:** If **live insertion** was active for the recording and the merged live buffer is **non-empty**, Ch4ttr **does not** run the WAV URL recognizer for that stop. It treats the live text as authoritative and only applies the usual **voice-command filter** and **`cleanupText`** polish (punctuation, dictionary, repeat collapse, etc.). If live insertion never worked or the live buffer is empty, Ch4ttr still falls back to **file-based** Apple Speech on the WAV so you get a transcript when streaming did not populate the field.

---

## What is reasonably exercised vs. not guaranteed

**In development / automated checks**

- Unit tests exist for pieces such as **cleanup** (spacing, repeat collapse, dictionary) and **voice command** parsing. Build + test via `xcodebuild` as above.
- Core flows (start/stop recording, paste path, settings persistence) are developed against typical macOS text fields.

**Not exhaustively tested (treat as best-effort)**

- **Every third-party app**’s accessibility text model (web inputs, Electron, IDEs, terminals, rich text). Insertion uses `AX` attributes when possible and falls back to clipboard + selection heuristics—edge cases exist.
- **All languages** end-to-end: settings include **English** and **Hebrew**; other locales depend on engine support and OS speech packs.
- **Long sessions**, **sleep/wake**, **multiple displays**, and **Screen Recording**-adjacent policies.
- **Release distribution**: notarization, stapling, and App Store review are **out of scope** for this README unless you add a release pipeline.
- **Groq / OpenAI** behavior under quota failures, rate limits, and regional blocks.
- **Whisper Core ML** bundles across every Apple Silicon generation (ANE availability varies).

Contributors: if you validate a configuration, add a short note under **Verified setups** in a PR.

---

## Advanced: Core ML encoder for whisper.cpp (optional)

`whisper.cpp` can run the **encoder** on the Apple Neural Engine via Core ML. That produces a compiled `.mlmodelc` bundle the sidecar can load next to your GGML model.

### Prereqs

- Xcode + CLI tools: `xcode-select --install`
- Python 3.11+ recommended

### Generate a Core ML encoder (example: `base.en`)

From a checkout of [whisper.cpp](https://github.com/ggml-org/whisper.cpp):

```bash
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

python3 -m venv .venv
source .venv/bin/activate

pip install ane_transformers openai-whisper coremltools

./models/generate-coreml-model.sh base.en
```

This yields something like `models/ggml-base.en-encoder.mlmodelc`.

### Build whisper.cpp with Core ML

```bash
cmake -B build -DWHISPER_COREML=1
cmake --build build -j --config Release
```

Ch4ttr’s sidecar must be built with **`WHISPER_COREML=1`** and the matching `.mlmodelc` must follow whisper.cpp’s expected layout next to the `.bin` model so the binary can load it. The Xcode project copies `Ch4ttr/Sidecars/whisper-cpp` into the app bundle when that file exists.

---

## Contributing

Issues and PRs welcome. Please keep changes focused, match existing Swift style, and extend tests when you change deterministic text or command behavior.

---

## Acknowledgements

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) for the local inference stack used by the sidecar path.
