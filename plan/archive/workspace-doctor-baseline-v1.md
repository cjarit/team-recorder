# Workspace Doctor Baseline — Team Recorder v1.0

Captured: 2026-05-26 (pre-restructure, Phase 1 of public-release plan)

## Present and aligned
- `core`: CLAUDE.md ✓, AGENTS.md ✓, README.md ✓, .gitignore ✓
- `claude_config`: .claude/ ✓ (settings.local.json present, gitignored)
- `CLAUDE.md identity`: no first-person identity phrases in first 30 lines ✓

## Functional equivalents (migration sources)
- `docs/plans/` → pre-template `plan/` equivalent → migrated to `plan/archive/`
- `docs/dev/` → functional `project-context/` equivalent → migrated to `project-context/`
- `docs/archive/` → empty → removed

## Missing (created in Phase 1)
- `project-context/` — overview.md, stakeholders.md, tech-stack.md, glossary.md, repo-structure.md, release-checklist.md
- `plan/` — NOW.md, DECISIONS.md, LESSONS.md, CHANGELOG.md, archive/

## Explicitly skipped
- wiki/, memory/, inbox/, design/, deliverables/ — not needed
- .mcp.json, CLAUDE.local.md.example, plan/SPEC.md — deferred

## Flags resolved
- `packaging/` — described "Phase 3E" work = this release; moved to plan/archive/
- `dist/TeamRecorder.zip` — exists locally, correctly gitignored
