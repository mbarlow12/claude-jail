# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub Actions release workflow (manually triggered)
- Remote installer script with shell environment detection (Linux, macOS, WSL)
- Changelog helper script (`scripts/changelog`) for generating entries from commits
- Core bubblewrap sandbox functionality
- Four isolation profiles: minimal, standard, dev, paranoid
- Standalone bash script (`bin/claude-jail`)
- Zsh plugin for Oh My Zsh and plain zsh users
- Configuration via environment variables, config files, and CLI
- Comprehensive test suite with bats-core
- CI/CD with GitHub Actions
