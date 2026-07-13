# Task 4 Report: Contextual Tool Filtering

## Summary

Implemented contextual tool filtering to reduce `search_web` over-triggering by updating all tool descriptions with explicit usage guidance and adding a `_toolsForQuery()` helper that filters tools based on query keywords.

## What Was Implemented

1. **Updated all 9 tool descriptions** in `lib/tools/tool_definitions.dart` with explicit "Use this ONLY when..." guidance, including a specific "Do NOT use" clause for `searchWeb`.

2. **Added `_toolsForQuery(String query)` helper** in `lib/screens/assistant_screen.dart` that:
   - Always includes low-impact tools: `getTime`, `setAlarm`, `cancelAlarm`, `openSettings`, `takeScreenshot`, `openApp`
   - Only includes `getWeather` if query contains "weather", "temperature", or "forecast"
   - Only includes `sendSms` if query contains "send" AND ("sms" OR "text" OR "message")
   - Only includes `searchWeb` if query contains "search", "look up", "find online", or "google"

3. **Replaced `NovaTools.all`** (line 310) with `_toolsForQuery(text)` in the `processMessage` call.

4. **Added `flutter_gemma` import** in `assistant_screen.dart` to resolve `Tool` type reference.

## Files Changed

| File | Lines Changed | Description |
|------|--------------|-------------|
| `lib/tools/tool_definitions.dart` | Lines 22-155 | Updated all 9 tool descriptions |
| `lib/screens/assistant_screen.dart` | Line 20 (new import), lines 265-298 (new method), line 310 (call site) | Added `_toolsForQuery()` helper and replaced `NovaTools.all` |

## Test Results

```
flutter analyze
No issues found! (ran in 4.2s)
```

## Acceptance Criteria

- [x] `searchWeb.description` explicitly says "Use this ONLY when user explicitly asks to search"
- [x] All other tool descriptions explicitly say "Use this ONLY when user explicitly asks"
- [x] `NovaTools.all` is not passed unconditionally
- [x] `_toolsForQuery()` returns contextually filtered tools based on query keywords
- [x] Web search is only included when query contains search-related keywords

## Concerns

- The keyword-based filter is a simple heuristic. Queries like "what's the best way to find a good restaurant" would still not trigger search since "find" alone isn't in the keyword list. This is intentional — only explicit search requests trigger the tool. Edge cases may need refinement over time.
- The `searchWeb` tool description includes a negative instruction ("Do NOT use this") which is a strong signal to the model, but effectiveness depends on the Gemma model's instruction-following capability.
