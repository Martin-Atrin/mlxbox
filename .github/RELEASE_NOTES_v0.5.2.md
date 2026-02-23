## MLXBox v0.5.2

Runtime bootstrap reliability and diagnostics improvements.

### Fixed
- Executable resolution no longer relies only on `PATH`.
- Added explicit binary discovery for:
  - `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`
  - `/usr/bin/python3`, `/opt/homebrew/bin/python3`, `/usr/local/bin/python3`
- Improved bootstrap diagnostics with exact runtime paths and python executable used.

### Clarified
- Core MLX runtime dependencies install into:
  - `~/Library/Application Support/MLXBox/runtime/venv`
- Homebrew-managed components remain optional (`llmfit`, `whisper-cpp`).
