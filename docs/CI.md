# aiasm - CI and multi-platform notes

This repository now includes a GitHub Actions workflow to build and package artifacts for multiple platforms (Linux x86_64, Linux aarch64 (cross-build), macOS).

Workflow: .github/workflows/multi-platform-build.yml
- Trigger: push to master or manual workflow_dispatch (optionally provide `tag` to create a GitHub Release)
- Artifacts: tar.gz packages for each platform

Notes:
- Cross-build uses `aarch64-linux-gnu` toolchain available on Ubuntu. The Makefile is invoked with AS/LD/CC overrides.
- CI packages existing `bin/` and compiled `examples/`. The workflow does not execute compiled binaries on different architectures.

