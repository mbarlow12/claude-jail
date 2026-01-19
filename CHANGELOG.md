# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Git worktree support with automatic detection and main `.git` binding (`--git-root`, `--git-ro`)
- Configurable sandbox location via `CJ_SANDBOX_HOME` and `CJ_SANDBOX_NAME`

## [0.1.0] - 2026-01-16

Initial release of claude-jail: a bubblewrap sandbox for running Claude Code in isolation. Includes standalone bash CLI, Zsh plugin, four security profiles, and automated release tooling.
### Added
- Core bubblewrap sandbox with four isolation profiles (minimal, standard, dev, paranoid) ([8bb7395](https://github.com/mbarlow12/claude-jail/commit/8bb7395))
- Standalone bash script `bin/claude-jail` for non-Zsh users ([8bb7395](https://github.com/mbarlow12/claude-jail/commit/8bb7395))
- Zsh plugin for Oh My Zsh and plain zsh users ([ed7924f](https://github.com/mbarlow12/claude-jail/commit/ed7924f))
- Configuration via environment variables, config files, and CLI ([ed7924f](https://github.com/mbarlow12/claude-jail/commit/ed7924f))
- Remote installer with OS detection (Linux, macOS, WSL) ([7553c3c](https://github.com/mbarlow12/claude-jail/commit/7553c3c))
- Release workflow with version bumping and changelog management ([28d7389](https://github.com/mbarlow12/claude-jail/commit/28d7389))
- Changelog helper script `scripts/changelog` ([10e8c7d](https://github.com/mbarlow12/claude-jail/commit/10e8c7d))
- Comprehensive test suite with bats-core ([54715a1](https://github.com/mbarlow12/claude-jail/commit/54715a1))

