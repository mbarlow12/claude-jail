# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub Actions release workflow triggered on version tags
- Remote installer script with shell environment detection
- VERSION file as single source of truth
- CHANGELOG.md for tracking changes

## [0.1.0] - Unreleased

### Added
- Initial release
- Core bubblewrap sandbox functionality
- Four isolation profiles: minimal, standard, dev, paranoid
- Standalone bash script (`bin/claude-jail`)
- Zsh plugin for Oh My Zsh users
- Configuration via environment variables, config files, and CLI
- Comprehensive test suite with bats-core
- CI/CD with GitHub Actions
