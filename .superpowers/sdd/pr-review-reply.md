Addressed review feedback in latest commit (`c03541e`):

- Hard `maxTokens` cap in `buildReplayMessages` (including first message)
- Dropped `addQuery` fallback on `clearHistory` failure (defer via pending replay + clear chat)
- Persist image/tool-only assistant turns; filter streaming/error/empty shells only
- Consolidated keep-warm / high-context / auto-compact / adult-mode load into `_loadRuntimeSettings`
