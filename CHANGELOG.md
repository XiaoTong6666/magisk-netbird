# Changelog

## v1.2.0 (2026-09-22) — NetBird v0.79.0

- Rebuilt release pipeline: three official-binary builds (`x86_64` / `arm64-v8a` / `armv7`), packaged by GitHub Actions with sha256-verified downloads from the official NetBird releases.
- NetBird 0.74.2 → 0.79.0.
- In-app update banner: install-time per-architecture `updateJson` manifests (`update/update-*.json`), refreshed on every release.
- Fixes: upgrades now replace the bundled binary; `stop` removes all iptables/ip rules the module added; route rules compare route-table id vs name correctly (no more delete/re-add churn); dynamic `module.prop` description is kept on both the active and staged module directories; added `action.sh` (Magisk v28+ ACTION button).
- Settings: `NB_DISABLE_SSH_CONFIG`, `NB_SKIP_NFTABLES_CHECK`, `NB_SKIP_DNS_PROBE`, `NB_NETWORK_MONITOR`, `NB_STATE_DIR`; opt-in `NB_DISABLE_IPV6` / `NB_DISABLE_FIREWALL`.
- Legacy v1.0.x installs keep working: the root `update.json` now points at the arm64-v8a zip. Re-login may be required after upgrading from the old line.
