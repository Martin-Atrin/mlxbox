## MLXBox v0.5.1

Fixes runtime bootstrap behavior on systems without Homebrew.

### Fixed
- Homebrew is now optional for startup bootstrap.
- `llmfit` and `whisper-cpp` auto-install steps are marked as `skipped` (not failed) when Homebrew is unavailable.
- Bootstrap now continues step-by-step so optional component failures do not block Python/MLX runtime setup.
- Runtime health check no longer requires `llmfit`/`whisper-cpp`, preventing repeated failed bootstrap loops.

### Result
The packaged `.app` now runs even when Homebrew is not installed.
