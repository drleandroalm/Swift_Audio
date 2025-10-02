# Repository Guidelines

## Project Structure & Module Organization
- Sources: `Sources/AuroraCore`, `Sources/AuroraLLM`, `Sources/AuroraML`, `Sources/AuroraTaskLibrary`; executables under `Sources/AuroraExamples` and `Sources/Tools/ModelTrainer`.
- Tests: `Tests/*` mirrors module names (files end with `Tests.swift`).
- Docs: generated archives and web output in `docs/`; scripts: `generate-docs.sh`, `build-docs.sh`.
- Config: `.swiftlint.yml`, `.editorconfig` (Swift uses 4‑space indent), `.env.example` for local keys.

## Build, Test, and Development Commands
- Build all targets: `swift build` (add `-c release` for optimized builds).
- Run tests: `swift test` (filter: `swift test --filter AuroraLLMTests`).
- Run examples: `swift run AuroraExamples`.
- Run tools: `swift run ModelTrainer`.
- Docs quick build: `./generate-docs.sh`; full web export: `./build-docs.sh`.
- Env setup: `cp .env.example .env` then edit keys locally (do not commit).

## Coding Style & Naming Conventions
- Indentation: 4 spaces for `.swift` (see `.editorconfig`).
- Naming: Types `PascalCase`; methods/vars/properties `lowerCamelCase`; test types end with `Tests`.
- Linting: run `swiftlint` at repo root. Config opts‐in to rules like `trailing_whitespace`, `explicit_init`; disables `line_length` and `indentation_width`. Keep names ≥3 chars unless allowed in config.
- File layout: one primary type per file; filename matches type when possible.

## Testing Guidelines
- Framework: XCTest. Place tests under corresponding `Tests/<ModuleName>Tests`.
- Determinism: prefer mocks for LLM/ML; integration tests using real services are optional and must be guarded by env keys.
- Keys: add `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `OPENAI_API_KEY` to non‑shared schemes or local shell env. Ollama requires a local service at `http://localhost:11434`.
- Run specific tests often; add coverage for new public APIs and bug fixes.

## Commit & Pull Request Guidelines
- Commits: imperative, present tense, concise scope (e.g., “Add CoreML tagging service”, “Refactor Workflow reporting”). Link issues (`#123`) when relevant.
- PRs: clear description, rationale, and scope; include tests, updated docs/examples, and notes on configuration or breaking changes. Ensure `swift test` and `swiftlint` pass locally; add screenshots or logs for examples/tools when helpful.

## Security & Configuration Tips
- Never commit API keys or `.env`. Prefer unshared Xcode schemes or shell env vars.
- iOS 14+ / macOS 11+ targets; some features require newer OS versions.
