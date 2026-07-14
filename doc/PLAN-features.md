# Implementation Plan: Streaming Tool Results, Task Management, Note Taking, Document Analysis

> Generated from codebase audit of `nova_assistant` (v0.2.0)
> Date: 2026-07-14

---

## Table of Contents

1. [Streaming Tool Results](#1-streaming-tool-results)
2. [Task Management](#2-task-management)
3. [Note Taking](#3-note-taking)
4. [Document Analysis](#4-document-analysis)
5. [Shared Infrastructure](#5-shared-infrastructure)
6. [Implementation Order](#6-implementation-order)

---

## 1. Streaming Tool Results

### Current State

Tool execution is fire-and-forget. The flow is:

1. Model emits `FunctionCallResponse` or parsed JSON tool call
2. `ModelOrchestrator` calls `ToolExecutorService.executeTool()` (single await)
3. Result is returned all at once
4. Status is `'Executing tool_name...'` → `'done'`

**Files involved:**
- `lib/platform/tool_executor_service.dart` — Flutter side, uses `MethodChannel('dev.nova.assistant/tools')`
- `android/.../ToolExecutor.kt` — Native side, synchronous execution
- `lib/services/model_orchestrator.dart:1144-1251` — Tool call loop

**Problem:** No progress feedback during long-running tools (e.g., web search, weather API, file download). User sees only "Executing..." with no indication of progress.

### Architecture

```
┌─────────────────┐     MethodChannel      ┌──────────────────┐
│  Flutter (Dart)  │ ◄──────────────────► │  Android (Kotlin) │
│                  │                        │                   │
│ ToolExecutorSvc  │   invokeMethod()      │  ToolExecutor     │
│ .executeTool()   │ ──────────────────►   │  .when {}         │
│                  │                        │                   │
│                  │   ◄── result ───────  │  result.success() │
└─────────────────┘                        └──────────────────┘

Proposed addition:
┌─────────────────┐     EventChannel       ┌──────────────────┐
│  Flutter (Dart)  │ ◄──────────────────► │  Android (Kotlin) │
│                  │   progress events     │                   │
│ ToolProgressSvc  │ ◄──────────────────  │  ToolExecutor     │
│ .onProgress      │   {tool, pct, msg}   │  .sendProgress()  │
└─────────────────┘                        └──────────────────┘
```

### Plan

#### Step 1: Define progress model

Create `lib/models/tool_progress.dart`:

```dart
enum ToolProgressStage { starting, executing, processing, done, error }

class ToolProgress {
  final String toolName;
  final ToolProgressStage stage;
  final double? percent;    // 0.0 - 1.0
  final String? message;    // "Fetching search results..."
  final Map<String, dynamic>? data;

  const ToolProgress({
    required this.toolName,
    required this.stage,
    this.percent,
    this.message,
    this.data,
  });
}
```

#### Step 2: Add EventChannel for progress on Android

In `ToolExecutor.kt`, add a progress EventChannel alongside the existing MethodChannel:

```kotlin
private var progressEventSink: EventChannel.EventSink? = null

fun registerWith(messenger: BinaryMessenger, context: Context) {
    // Existing MethodChannel...
    EventChannel(messenger, "dev.nova.assistant/tools_progress")
        .setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                progressEventSink = null
            }
        })
}

private fun sendProgress(toolName: String, stage: String, percent: Double?, message: String?) {
    progressEventSink?.success(mapOf(
        "toolName" to toolName,
        "stage" to stage,
        "percent" to percent,
        "message" to message,
    ))
}
```

#### Step 3: Add progress callbacks to native tools

Update `getWeather()`, `searchWeb()`, and `sendSms()` to send progress:

```kotlin
private fun getWeather(args: Map<*, *>): Map<String, Any> {
    val location = args["location"] as? String ?: "current location"
    sendProgress("get_weather", "executing", 0.3, "Querying weather API...")
    // ... actual API call ...
    sendProgress("get_weather", "processing", 0.8, "Processing response...")
    // ... build result ...
    sendProgress("get_weather", "done", 1.0, null)
    return result
}
```

#### Step 4: Add progress stream to ToolExecutorService

```dart
class ToolExecutorService {
  static const _channel = MethodChannel('dev.nova.assistant/tools');
  static const _progressChannel = EventChannel('dev.nova.assistant/tools_progress');

  Stream<ToolProgress> get onProgress =>
      _progressChannel.receiveBroadcastStream()
          .map((event) => ToolProgress.fromMap(Map<String, dynamic>.from(event)));
}
```

#### Step 5: Stream progress in ModelOrchestrator

In `processMessage()`, subscribe to progress and yield intermediate results:

```dart
// Inside tool execution loop:
allToolCalls.add({
  'name': toolName,
  'args': toolArgs,
  'status': 'executing',
  'progress': 'Starting...',
});

// Subscribe to progress
final progressSub = ToolExecutorService.instance.onProgress
    .where((p) => p.toolName == toolName)
    .listen((progress) {
  allToolCalls.last['progress'] = progress.message;
  allToolCalls.last['progressPercent'] = progress.percent;
  // Yield a streaming update
  _progressController.add(InferenceResult(
    text: fullResponse,
    model: model,
    isStreaming: true,
    toolCalls: List.from(allToolCalls),
  ));
});

// After tool completes:
await progressSub.cancel();
allToolCalls.last['status'] = 'done';
```

#### Step 6: Update ChatBubble to show progress

Add a progress indicator to the tool call chip:

```dart
// In tool call chip rendering:
if (toolCall['status'] == 'executing' && toolCall['progress'] != null)
  LinearProgressIndicator(
    value: toolCall['progressPercent'] as double?,
    backgroundColor: Colors.grey[800],
    color: const Color(0xFF6C63FF),
  ),
```

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/models/tool_progress.dart` | **Create** | ToolProgress model |
| `lib/platform/tool_executor_service.dart` | Modify | Add progress EventChannel stream |
| `android/.../ToolExecutor.kt` | Modify | Add progress EventChannel + sendProgress() |
| `lib/services/model_orchestrator.dart` | Modify | Subscribe to progress, yield intermediate results |
| `lib/widgets/chat_bubble.dart` | Modify | Show progress bar in tool chip |
| `test/models/tool_progress_test.dart` | **Create** | Unit tests |

### Risk: Native EventChannel

The EventChannel approach requires the native side to push events. If the tool execution is synchronous (which most current tools are), we need to either:
- Use a CoroutineScope to make API calls async, or
- For simple tools (get_time, open_app), skip progress events entirely (they're instant)

**Decision:** Only add progress streaming for tools that genuinely take time: `get_weather`, `search_web`, `send_sms`. Others remain synchronous.

---

## 2. Task Management

### Current State

No task/to-do system exists. The app has:
- SharedPreferences for settings
- `sqflite` in pubspec.yaml (unused currently — SQLite available)
- `uuid` package for ID generation
- RAG memory system (keyword-based)

### Architecture

```
lib/
  models/
    task.dart                    # NEW: Task data model
  services/
    task_service.dart            # NEW: CRUD + persistence
  screens/
    tasks_screen.dart            # NEW: Task list + detail
  tools/
    tool_definitions.dart        # MODIFY: Add task tools

android/
  app/src/main/kotlin/.../
    ToolExecutor.kt              # MODIFY: Handle task tool calls
```

### Plan

#### Step 1: Create Task model

`lib/models/task.dart`:

```dart
enum TaskPriority { low, medium, high }
enum TaskStatus { pending, inProgress, completed, cancelled }

class Task {
  final String id;
  String title;
  String? description;
  TaskPriority priority;
  TaskStatus status;
  DateTime createdAt;
  DateTime? dueDate;
  DateTime? completedAt;
  List<String> tags;

  // copyWith, toJson, fromJson, equality
}
```

#### Step 2: Create TaskService

`lib/services/task_service.dart`:

```dart
class TaskService {
  static TaskService? _instance;
  static TaskService get instance => _instance ??= TaskService._();
  TaskService._();

  static const _prefsKey = 'nova_tasks';
  final _tasksController = StreamController<List<Task>>.broadcast();
  Stream<List<Task>> get tasksStream => _tasksController.stream;

  List<Task> _tasks = [];

  Future<void> initialize() async { /* load from prefs */ }

  Future<Task> createTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    List<String> tags = const [],
  }) async { /* generate ID, persist, notify */ }

  Future<void> updateTask(Task task) async { /* persist, notify */ }

  Future<void> completeTask(String taskId) async { /* set status, persist */ }

  Future<void> deleteTask(String taskId) async { /* remove, notify */ }

  List<Task> getActiveTasks() => _tasks.where((t) =>
      t.status == TaskStatus.pending || t.status == TaskStatus.inProgress
  ).toList();

  List<Task> searchTasks(String query) { /* keyword match */ }
}
```

**Storage:** SharedPreferences with JSON list (consistent with existing pattern — MemoryService, ChatHistoryService, McpService all use this). SQLite is available but overkill for a task list.

#### Step 3: Create Tasks screen

`lib/screens/tasks_screen.dart`:

```dart
class TasksScreen extends StatefulWidget {
  // Full-screen list with:
  // - Filter bar (All / Pending / Completed)
  // - Sort by (Date / Priority / Name)
  // - FAB to create task
  // - Swipe to complete/delete
  // - Tap to edit
}
```

**UI components:**
- `TaskCard` — displays title, priority badge, due date, tags
- `TaskDetailSheet` — bottom sheet for editing
- `CreateTaskDialog` — form with title, description, priority, due date, tags

#### Step 4: Add AI tools for tasks

In `lib/tools/tool_definitions.dart`, add:

```dart
static final Tool createTask = Tool(
  name: 'create_task',
  description: 'Create a new to-do task. '
      'Use this ONLY when the user asks to create, add, or remember a task.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Task title'},
      'description': {'type': 'string', 'description': 'Task details'},
      'priority': {'type': 'string', 'enum': ['low', 'medium', 'high']},
      'due_date': {'type': 'string', 'description': 'ISO 8601 date string'},
    },
    'required': ['title'],
  },
);

static final Tool listTasks = Tool(
  name: 'list_tasks',
  description: 'List pending tasks. '
      'Use this when the user asks about their tasks, to-dos, or what they need to do.',
  parameters: {'type': 'object', 'properties': {}},
);

static final Tool completeTask = Tool(
  name: 'complete_task',
  description: 'Mark a task as completed.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Title of task to complete (fuzzy match)'},
    },
    'required': ['title'],
  },
);
```

#### Step 5: Handle tool calls in ToolExecutor (Kotlin)

Add task tools to `ToolExecutor.kt`:

```kotlin
"create_task" -> createTask(args)
"list_tasks" -> listTasks()
"complete_task" -> completeTask(args)
```

These are **Dart-only tools** — they don't need native Android execution. The tool execution should route through Dart, not Kotlin. Better approach:

In `ModelOrchestrator`, intercept task tools before reaching `ToolExecutorService`:

```dart
// In the tool execution loop:
if (toolName == 'create_task' || toolName == 'list_tasks' || toolName == 'complete_task') {
  toolResult = await _executeTaskTool(toolName, toolArgs);
} else {
  // Existing MCP → native flow
}
```

This keeps task logic in Dart where it's easier to manage.

#### Step 6: Add navigation entry

In `settings_screen.dart` or as a new tab, add a "Tasks" entry that navigates to `TasksScreen`.

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/models/task.dart` | **Create** | Task data model |
| `lib/services/task_service.dart` | **Create** | CRUD + persistence |
| `lib/screens/tasks_screen.dart` | **Create** | Task list UI |
| `lib/tools/tool_definitions.dart` | Modify | Add createTask, listTasks, completeTask |
| `lib/services/model_orchestrator.dart` | Modify | Intercept task tool calls |
| `lib/screens/settings_screen.dart` | Modify | Add Tasks navigation entry |
| `test/models/task_test.dart` | **Create** | Unit tests |
| `test/services/task_service_test.dart` | **Create** | Service tests |

---

## 3. Note Taking

### Current State

No note-taking system exists. The app has:
- Custom memories system (`MemoryService.getCustomMemories()`) — but these are simple key-value facts, not structured notes
- File attachment support for reading text files
- Markdown rendering via `flutter_markdown`

### Architecture

Same pattern as Task Management. Notes are a first-class data entity with their own screen, service, and AI tools.

### Plan

#### Step 1: Create Note model

`lib/models/note.dart`:

```dart
class Note {
  final String id;
  String title;
  String content;        // Markdown content
  List<String> tags;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;

  // copyWith, toJson, fromJson
}
```

#### Step 2: Create NoteService

`lib/services/note_service.dart`:

```dart
class NoteService {
  static NoteService? _instance;
  static NoteService get instance => _instance ??= NoteService._();
  NoteService._();

  static const _prefsKey = 'nova_notes';
  final _notesController = StreamController<List<Note>>.broadcast();
  Stream<List<Note>> get notesStream => _notesController.stream;

  List<Note> _notes = [];

  Future<void> initialize() async { /* load */ }

  Future<Note> createNote({
    required String title,
    required String content,
    List<String> tags = const [],
    bool isPinned = false,
  }) async { /* generate, persist, notify */ }

  Future<void> updateNote(Note note) async { /* persist, notify */ }

  Future<void> deleteNote(String noteId) async { /* remove, notify */ }

  List<Note> searchNotes(String query) {
    final lower = query.toLowerCase();
    return _notes.where((n) =>
        n.title.toLowerCase().contains(lower) ||
        n.content.toLowerCase().contains(lower) ||
        n.tags.any((t) => t.toLowerCase().contains(lower))
    ).toList();
  }

  List<Note> getNotesByTag(String tag) =>
      _notes.where((n) => n.tags.contains(tag)).toList();
}
```

#### Step 3: Create Notes screen

`lib/screens/notes_screen.dart`:

```dart
class NotesScreen extends StatefulWidget {
  // Grid/List toggle view
  // - Search bar
  // - Tag filter chips
  // - Pinned notes section at top
  // - FAB to create new note
  // - Tap to open note editor
  // - Long-press for context menu (delete, pin, share)
}
```

**UI components:**
- `NoteCard` — shows title, preview, tags, pin indicator
- `NoteEditor` — full-screen editor with Markdown support
- `TagFilter` — horizontal scrollable tag chips

#### Step 4: Add AI tools for notes

```dart
static final Tool createNote = Tool(
  name: 'create_note',
  description: 'Create a new note. '
      'Use this when the user asks to save, remember, or note something down.',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Note title'},
      'content': {'type': 'string', 'description': 'Note content (Markdown)'},
      'tags': {'type': 'string', 'description': 'Comma-separated tags'},
    },
    'required': ['title', 'content'],
  },
);

static final Tool searchNotes = Tool(
  name: 'search_notes',
  description: 'Search through notes. '
      'Use this when the user asks to find, look up, or recall saved notes.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search query'},
    },
    'required': ['query'],
  },
);

static final Tool listNotes = Tool(
  name: 'list_notes',
  description: 'List recent or pinned notes.',
  parameters: {'type': 'object', 'properties': {}},
);
```

#### Step 5: Intercept note tools in orchestrator

Same pattern as tasks — intercept before reaching native:

```dart
if (toolName == 'create_note' || toolName == 'search_notes' || toolName == 'list_notes') {
  toolResult = await _executeNoteTool(toolName, toolArgs);
}
```

#### Step 6: Integrate with Memory system

Optionally, important notes could be surfaced via the RAG memory system. When a note is created, it could be indexed for retrieval:

```dart
// In NoteService.createNote:
await MemoryService.storeConversation(
  '[Note saved] $title',
  content,
);
```

This way, if a user asks "what did I write about X?", the RAG system can retrieve relevant notes.

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/models/note.dart` | **Create** | Note data model |
| `lib/services/note_service.dart` | **Create** | CRUD + persistence |
| `lib/screens/notes_screen.dart` | **Create** | Notes list/editor UI |
| `lib/tools/tool_definitions.dart` | Modify | Add createNote, searchNotes, listNotes |
| `lib/services/model_orchestrator.dart` | Modify | Intercept note tool calls |
| `lib/screens/settings_screen.dart` | Modify | Add Notes navigation entry |
| `test/models/note_test.dart` | **Create** | Unit tests |
| `test/services/note_service_test.dart` | **Create** | Service tests |

---

## 4. Document Analysis

### Current State

`attached_data.dart` handles file attachments. Currently supports:
- Text files (`.txt`, `.md`, `.json`, `.csv`, etc.) — full content read
- Images (`.jpg`, `.png`, etc.) — pass to vision model
- PDF — **placeholder only**: returns `"[File: name.pdf (PDF - X MB)]"`
- Other files — placeholder

**The `sqflite` package is available** but unused. Could be used for document indexing.

### Architecture

```
┌─────────────────┐
│  AttachedData    │  Existing file attachment
│  .buildContext() │
└────────┬────────┘
         │
    ┌────▼────┐
    │ Extract │  NEW: PDF/document text extraction
    │ Text    │
    └────┬────┘
         │
    ┌────▼────────┐
    │ Chunk &     │  NEW: Split into context-window-sized chunks
    │ Index       │
    └────┬────────┘
         │
    ┌────▼────────┐
    │ Query &     │  NEW: When user asks about the document,
    │ Retrieve    │  find relevant chunks and inject into context
    └─────────────┘
```

### Plan

#### Step 1: Add PDF text extraction

Add `pdf_text` or `syncfusion_flutter_pdf` package to `pubspec.yaml`:

```yaml
dependencies:
  syncfusion_flutter_pdf: ^28.0.0   # For PDF text extraction
```

**Alternative:** Use `pdfx` for read-only extraction, or platform channel to use Android's native PDF rendering.

**Recommended:** `syncfusion_flutter_pdf` — pure Dart, no native code needed, works on all platforms.

#### Step 2: Create DocumentExtractor service

`lib/services/document_extractor.dart`:

```dart
class DocumentExtractor {
  /// Extract text from a file based on its extension.
  static Future<String> extractText(String filePath, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();

    switch (ext) {
      case 'pdf':
        return _extractPdf(filePath);
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'xml':
      case 'yaml':
      case 'yml':
        return await File(filePath).readAsString();
      case 'docx':
        return _extractDocx(filePath);
      default:
        return '[Unsupported file type: .$ext]';
    }
  }

  static Future<String> _extractPdf(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '[PDF file not found]';

    // Using syncfusion_flutter_pdf:
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final buffer = StringBuffer();

    for (int i = 0; i < document.pages.count; i++) {
      final text = document.pages[i].extractText();
      buffer.writeln(text);
      buffer.writeln('\n--- Page ${i + 1} ---\n');
    }

    document.dispose();

    final result = buffer.toString();
    return result.length > 10000
        ? '${result.substring(0, 10000)}\n\n... (truncated, ${result.length} chars total)'
        : result;
  }

  static Future<String> _extractDocx(String filePath) async {
    // Basic DOCX extraction (ZIP → XML → text)
    // For MVP, return placeholder
    return '[DOCX extraction not yet implemented]';
  }
}
```

#### Step 3: Update AttachedData.buildContext()

Modify `attached_data.dart` to use `DocumentExtractor`:

```dart
Future<String> _buildFileContext() async {
  if (filePath == null) return '[File: $name (path unknown)]';

  final file = File(filePath!);
  if (!await file.exists()) return '[File: $name (not found)]';

  final ext = name.split('.').last.toLowerCase();

  // Images → pass to vision model (existing)
  if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
    return '[Image: $name]';
  }

  // All text-based + PDF → extract text
  final extracted = await DocumentExtractor.extractText(filePath!, name);
  final preview = extracted.length > 5000
      ? '${extracted.substring(0, 5000)}\n\n... (truncated)'
      : extracted;
  return '[File: $name]\n```\n$preview\n```';
}
```

#### Step 4: Add document query tool

For querying specific documents (rather than just attaching them):

```dart
static final Tool queryDocument = Tool(
  name: 'query_document',
  description: 'Ask a question about an attached document. '
      'Use this when the user asks about content in a file they\'ve attached.',
  parameters: {
    'type': 'object',
    'properties': {
      'document_name': {'type': 'string', 'description': 'Name of the attached file'},
      'question': {'type': 'string', 'description': 'Question about the document'},
    },
    'required': ['document_name', 'question'],
  },
);
```

#### Step 5: Implement document chunking for large files

For documents that exceed the context window, implement chunking:

```dart
class DocumentChunker {
  static List<String> chunk(String text, {int maxChunkSize = 2000, int overlap = 200}) {
    if (text.length <= maxChunkSize) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = start + maxChunkSize;
      if (end > text.length) end = text.length;

      // Try to break at paragraph or sentence
      if (end < text.length) {
        final lastNewline = text.lastIndexOf('\n', end);
        final lastPeriod = text.lastIndexOf('. ', end);
        if (lastNewline > start + maxChunkSize ~/ 2) {
          end = lastNewline + 1;
        } else if (lastPeriod > start + maxChunkSize ~/ 2) {
          end = lastPeriod + 2;
        }
      }

      chunks.add(text.substring(start, end).trim());
      start = end - overlap;
    }

    return chunks;
  }
}
```

#### Step 6: Enhanced query flow for document questions

When `query_document` is called:

```dart
Future<Map<String, dynamic>> _executeDocumentQuery(
  String documentName, String question,
) async {
  // Find the attachment
  final attachment = AttachmentManager.instance.attachments
      .where((a) => a.name == documentName)
      .firstOrNull;

  if (attachment == null) {
    return {'success': false, 'error': 'Document not found: $documentName'};
  }

  // Extract text
  final text = await DocumentExtractor.extractText(
    attachment.filePath!, attachment.name,
  );

  // Chunk it
  final chunks = DocumentChunker.chunk(text);

  // Simple relevance scoring (keyword match)
  final questionWords = question.toLowerCase().split(RegExp(r'\s+')).toSet();
  final scoredChunks = chunks.map((chunk) {
    final chunkLower = chunk.toLowerCase();
    final matches = questionWords.where((w) => chunkLower.contains(w)).length;
    return MapEntry(chunk, matches / questionWords.length);
  }).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Take top 3 relevant chunks
  final relevant = scoredChunks
      .take(3)
      .where((s) => s.value > 0)
      .map((s) => s.key)
      .join('\n\n');

  if (relevant.isEmpty) {
    return {
      'success': true,
      'answer': 'Could not find relevant content in $documentName for: $question',
    };
  }

  return {
    'success': true,
    'relevantContent': relevant,
    'hint': 'Use this content to answer the user\'s question.',
  };
}
```

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/services/document_extractor.dart` | **Create** | PDF/document text extraction |
| `lib/models/attached_data.dart` | Modify | Use DocumentExtractor in _buildFileContext |
| `lib/tools/tool_definitions.dart` | Modify | Add queryDocument tool |
| `lib/services/model_orchestrator.dart` | Modify | Handle queryDocument tool calls |
| `lib/services/document_chunker.dart` | **Create** | Text chunking utility |
| `pubspec.yaml` | Modify | Add syncfusion_flutter_pdf dependency |
| `test/services/document_extractor_test.dart` | **Create** | Unit tests |
| `test/services/document_chunker_test.dart` | **Create** | Unit tests |

### Risk: PDF Package Size

`syncfusion_flutter_pdf` is a large package (~15MB). Alternatives:

| Package | Size | Pros | Cons |
|---------|------|------|------|
| `syncfusion_flutter_pdf` | ~15MB | Full PDF support, pure Dart | Large, commercial license for production |
| `pdf_text` | ~2MB | Lightweight | Limited PDF support |
| Platform channel (Android PDF renderer) | ~0MB | No Flutter dependency | Android-only, more code |

**Decision:** Start with `syncfusion_flutter_pdf` for MVP, evaluate alternatives later. For web/desktop, a pure Dart solution is preferable.

---

## 5. Shared Infrastructure

### Database Migration

All three new features (tasks, notes, document index) currently plan to use SharedPreferences with JSON. If the data grows or needs complex queries, migrate to SQLite:

```dart
// Future: if tasks/notes grow large, use sqflite
final db = await openDatabase(
  path.join(await getDatabasesPath(), 'nova.db'),
  version: 1,
  onCreate: (db, version) {
    db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT, ...)');
    db.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, ...)');
  },
);
```

**Decision:** Start with SharedPreferences for consistency. Migrate to SQLite only if performance issues arise.

### Settings Integration

Add settings toggles in `settings_screen.dart`:

```dart
// Task Management section
SwitchListTile(
  title: const Text('Task Management'),
  subtitle: const Text('Create and track to-do items'),
  value: _taskManagementEnabled,
  onChanged: (v) { /* toggle */ },
),

// Note Taking section
SwitchListTile(
  title: const Text('Note Taking'),
  subtitle: const Text('Save and organize notes'),
  value: _noteTakingEnabled,
  onChanged: (v) { /* toggle */ },
),
```

### AI Tool Registration

All new tools need to be registered in `tool_definitions.dart` and routed in `model_orchestrator.dart`. The orchestrator already handles MCP tools vs native tools — task/note tools will be a third category:

```dart
// In _sendToolResponse / tool execution loop:
if (TaskService.isTaskTool(toolName)) {
  toolResult = await TaskService.instance.executeTool(toolName, toolArgs);
} else if (NoteService.isNoteTool(toolName)) {
  toolResult = await NoteService.instance.executeTool(toolName, toolArgs);
} else if (DocumentExtractor.isDocumentTool(toolName)) {
  toolResult = await _executeDocumentQuery(...);
} else {
  // Existing MCP → native flow
}
```

---

## 6. Implementation Order

### Phase A: Streaming Tool Results (1-2 days)

1. Create `tool_progress.dart` model
2. Add EventChannel to `ToolExecutor.kt`
3. Add progress stream to `ToolExecutorService`
4. Subscribe to progress in `ModelOrchestrator`
5. Update `ChatBubble` progress display
6. Test with `get_weather` and `search_web`

### Phase B: Document Analysis (2-3 days)

1. Add `syncfusion_flutter_pdf` to pubspec.yaml
2. Create `document_extractor.dart`
3. Update `AttachedData._buildFileContext()`
4. Create `document_chunker.dart`
5. Add `queryDocument` tool
6. Handle in orchestrator
7. Test with sample PDFs

### Phase C: Task Management (2-3 days)

1. Create `task.dart` model
2. Create `task_service.dart`
3. Create `tasks_screen.dart` with full UI
4. Add AI tools (createTask, listTasks, completeTask)
5. Handle in orchestrator
6. Add navigation entry
7. Tests

### Phase D: Note Taking (2-3 days)

1. Create `note.dart` model
2. Create `note_service.dart`
3. Create `notes_screen.dart` with editor
4. Add AI tools (createNote, searchNotes, listNotes)
5. Handle in orchestrator
6. Add navigation entry
7. Integrate with MemoryService for RAG
8. Tests

### Total estimated effort: 7-11 days

---

## Appendix: Dependency Graph

```
Streaming Tool Results ─── (independent, no new packages)
                              │
Document Analysis ─────────────┤
  └─ syncfusion_flutter_pdf    │
                              │
Task Management ──────────────┤
  └─ (uses existing prefs)    │
                              │
Note Taking ──────────────────┘
  └─ (uses existing prefs)
```

All four features are independent and can be developed in parallel. The only shared touchpoint is `ModelOrchestrator.toolExecutionLoop` where new tool categories are routed.
