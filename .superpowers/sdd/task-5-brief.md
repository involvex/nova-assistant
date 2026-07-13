# Task 5: Final Verification

## Goal

Run full project verification to ensure all changes from Tasks 1-4 are clean and consistent.

## Commands to Run

1. `flutter analyze` — full project static analysis (no file-specific args)
2. `dart format --set-exit-if-changed .` — verify all files are properly formatted
3. `git status` — confirm no uncommitted changes
4. `git log --oneline -5` — list recent commits for the report

## What to Report

- Full `flutter analyze` output (pass/fail)
- Full `dart format --set-exit-if-changed .` output (pass/fail)
- `git status` output
- `git log --oneline -5` output

## If Issues Found

- If `flutter analyze` reports errors, fix them
- If `dart format` reports changes needed, run `dart format .` then commit
- Commit any fixes with message: "chore: fix lint and formatting issues"

## Files That May Need Attention

Based on Tasks 1-4, these files were modified:
- `lib/services/model_orchestrator.dart` (Task 1)
- `lib/screens/onboarding_screen.dart` (Task 2, new file)
- `lib/main.dart` (Task 2)
- `lib/services/parallel_session_manager.dart` (Task 3)
- `lib/tools/tool_definitions.dart` (Task 4)
- `lib/screens/assistant_screen.dart` (Task 4)