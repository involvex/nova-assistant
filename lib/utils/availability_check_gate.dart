/// Debounce for the model-availability disk check.
///
/// During a cold engine load the orchestrator emits many status events
/// (`Loading…`, `Freeing memory…`, `Preparing chat session…`), and each one
/// currently re-stats every model file on disk plus a `setState`. On a
/// fresh chat — exactly when the device is already saturated by
/// `litert_lm_engine_create` — that extra I/O + rebuild work shows up as
/// `QueueBuffer timeout` jank. Installed-model state only changes on
/// install/delete (both resume the screen), so re-checking at most every
/// [minInterval] is plenty; [force] covers init/resume.
bool shouldRunAvailabilityCheck({
  required DateTime now,
  required DateTime? lastRun,
  required bool force,
  Duration minInterval = const Duration(seconds: 20),
}) {
  if (force || lastRun == null) {
    return true;
  }

  return now.difference(lastRun) >= minInterval;
}
