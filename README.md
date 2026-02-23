# MLXBox

MLXBox is a minimal macOS harness around MLX and MLX-LM.

Design goal:
- Lowest possible host footprint.
- Keep the app as a thin wrapper around local runtime tools.
- Avoid unnecessary background work and avoid swap-heavy defaults.

What it does:

- Assesses machine capability (memory, cores, bandwidth estimate)
- Blends MLX Community availability + fit scoring + llmfit scenario recommendations in one `Models` screen
- Bridges to [`llmfit`](https://github.com/AlexsJones/llmfit) when installed
- Pulls `mlx-community` model catalog from Hugging Face collections/API
- Adds secondary embedding discovery from Hugging Face `feature-extraction` feed (MLX-signaled models)
- Auto-categorizes models (chat, coding, reasoning, embedding, multimodal, speech, etc.)
- Marks models as `Trainable` for MLX-LM post-training workflows
- One-click model install/delete from within the app
- Runs local `mlx_lm.server` for downloaded models so chat works out-of-the-box
- Supports inference with base model + LoRA adapter (`--adapter-path`) in chat
- Includes MLX-LM post-training tools (dataset scaffold + LoRA run)
- Scans localhost for model endpoints
- Provides a minimal OpenAI-compatible local chat surface
- Auto-bootstrap runtime dependencies on launch (best effort)

## Project Status

This is an MVP focused on low-friction local inference and post-training.

## Build (Xcode CLI)

```bash
xcodebuild \
  -project MLXBox.xcodeproj \
  -scheme MLXBox \
  -configuration Release \
  -derivedDataPath build \
  build
```

Expected bundle location:

`build/Build/Products/Release/MLXBox.app`

## Notes

- `llmfit` is optional. If unavailable, MLXBox uses built-in estimation heuristics.
- Startup bootstrap tries to install: `llmfit`, `whisper-cpp`, and Python runtime packages (`mlx`, `mlx-lm[train]`, `huggingface_hub[cli]`).
- Chat assumes an OpenAI-compatible local endpoint (`/v1/chat/completions`).
- Model fit estimates are conservative and aimed at avoiding swap.

## Post-Training

`Post-Training` tab supports:

- `train.jsonl` dataset scaffolding with format examples (`chat`, `completions`, `text`, `tools`)
- launching `mlx_lm.lora` against downloaded local models
- saving adapters under `~/Library/Application Support/MLXBox/training-runs/`

MLX-LM LoRA family support reference:
- Llama, Mistral, Mixtral, Phi, Qwen, Gemma, OLMo, MiniCPM, InternLM

## Package Release

Build, sign, and package a downloadable zip:

```bash
./scripts/package_release.sh
```

For distribution-quality signing, export `SIGN_IDENTITY` with your Developer ID Application certificate and notarize the zip before release.
