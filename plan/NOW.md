# Now — Team Recorder

## Current focus

**v1.0 public-GitHub release** — making the app installable from GitHub Releases on a clean macOS 14 Sonoma machine with no Homebrew/Python dependency.

## Phase status

| Phase | Status | Description |
|---|---|---|
| 0 — Pre-flight | ✅ Done | Git constraint confirmed, decisions locked |
| 1 — Workspace triage | ✅ Done | Template adoption, file moves, cross-ref sweep, Makefile Python fix |
| 2 — macOS 14 compat | ⚠ Smoke test deferred | All code aligned to 14; Sonoma device unavailable — smoke test before Phase 6 release |
| 3 — Clean-Mac requirements | ✅ Done | EARS spec in project-context/requirements-public-release.md |
| 4 — Packaging implementation | ✅ Done | Bundle paths, watcher.pyz, .env dual-source, preflight UX |
| 5 — Public docs rewrite | ✅ Done | README Releases-first, setup.md, faq.md (new), CLAUDE.md, CHANGELOG |
| 6 — Release build + publish | — | make release, v1.0.0 GitHub Release |

## Open items before Phase 6

- [ ] **Gatekeeper screenshot** — capture the right-click → Open dialog on a real macOS 14 Sonoma machine during Phase 6 smoke test; save as `docs/user/images/gatekeeper-bypass.png`. Placeholder already in README and setup.md.
- [ ] **Sonoma smoke test** — device unavailable; must be completed before tagging v1.0.0 (see Phase 2 note).

## Blocking decisions made

- Code signing: **ad-hoc** (right-click Open Gatekeeper bypass documented in README)
- Python bundling: **Plan A = zipapp** + system Python 3; fallback = PyInstaller
- Minimum macOS: **14 Sonoma**
- No commits until Phase 6
