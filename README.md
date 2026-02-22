# Discourse AI Persistent Memory v2

A Discourse plugin that gives AI personas persistent, cross-conversation memory about each user. Memories are automatically compressed into a profile summary that's injected into every conversation, so the AI inherently *knows* the user without needing to look anything up.

## Architecture

The plugin operates on two layers:

**Layer 1: Ambient Memory (always injected)**
A compressed profile paragraph (~200 words) is automatically injected into every AI conversation's system prompt. This gives the AI instant awareness of the user's preferences, expertise, current projects, and communication style — without consuming significant tokens or requiring a tool call.

**Layer 2: Detailed Memory (searchable on demand)**
The full memory store (up to 100 entries) remains available via the `memory` tool for specific lookups when the conversation needs detail beyond what the summary captures.

### How it works

1. **Memory writes** — When the AI stores a memory (or the user adds one manually), the memory is saved to PluginStore and a background job fires to regenerate the profile summary.
2. **Summary generation** — A fast, cheap LLM (Haiku/Flash) reads all memories and produces a concise prose paragraph. This is stored alongside the memories.
3. **Prompt injection** — On every AI conversation, the plugin prepends to `craft_prompt` and injects the summary into the system prompt via `custom_instructions`. The AI just *knows* the user.
4. **Consolidation** — When a user's memory count hits the configured limit, a background job sends all memories to the LLM for deduplication, merging, and cleanup. The cleaned set replaces the old memories, and the summary regenerates.

## Requirements

- Discourse (latest)
- discourse-ai plugin (bundled in core)

## Installation

Add to your `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/BrianCraword/discourse-ai-persistent-memory.git
```

Then rebuild:

```bash
./launcher rebuild app
```

## Configuration

### 1. Set the LLM Model (Required)

Go to **Admin → Settings** and search for `ai persistent memory`:

- **`ai_persistent_memory_llm_model_id`** — Set this to the ID of a fast, inexpensive LLM model. Go to Admin → AI → LLMs to find the model ID. Recommended: Claude Haiku, Gemini Flash, or similar.
- **`ai_persistent_memory_max_memories`** — Maximum memories per user (default: 100)
- **`ai_persistent_memory_max_value_length`** — Max characters per memory value (default: 500)
- **`ai_persistent_memory_consolidation_target`** — Target memory count after consolidation (default: 60)

### 2. Create the AI Tool

Go to **Admin → AI → Tools → New Tool** and create:

**Name:** `memory`

**Description:** Store and retrieve persistent memories about the user across conversations. Use this to remember preferences, facts, and context.

**Script:**

```javascript
function invoke(params) {
  const action = params.action;
  const key = params.key;
  const value = params.value;
  const query = params.query;

  if (action === "set") {
    if (!key || !value) return { error: "Key and value required" };
    return memory.set(key, value);
  } else if (action === "get") {
    if (!key) return { error: "Key required" };
    return { value: memory.get(key) };
  } else if (action === "list") {
    return { memories: memory.list() };
  } else if (action === "delete") {
    if (!key) return { error: "Key required" };
    return memory.delete(key);
  } else if (action === "search") {
    if (!query) return { error: "Query required" };
    return { results: memory.search(query) };
  }
  return { error: "Invalid action. Use: set, get, list, delete, search" };
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| action | string | yes | One of: set, get, list, delete, search |
| key | string | no | The memory key (for set, get, delete) |
| value | string | no | The value to store (for set) |
| query | string | no | Search query (for search) |

### 3. Enable on Personas

Edit your AI persona and:

1. Add the `memory` tool to enabled tools
2. Add memory instructions to the system prompt:

```
You have access to a persistent memory system. A summary of what you know about this
user is automatically provided to you. For specific details or to store new information,
use the memory tool:

- memory.set(key, value) — Remember a new fact
- memory.get(key) — Look up a specific memory
- memory.search(query) — Search memories by keyword
- memory.list() — See all stored memories
- memory.delete(key) — Remove a memory

Proactively save important user preferences, interests, and context when they share them.
You don't need to announce that you're saving a memory unless the user asks.
```

## User Interface

Users can view and manage their memories at:
**Preferences → Interface → AI Memory**

The UI shows:
- Current memory count and limit
- Expandable summary panel showing the AI-generated profile paragraph
- Filterable memory table with delete buttons
- Add memory form

## Upgrading from v1

This version uses the same PluginStore namespace (`ai_user_memory_{user_id}`) as v1. Existing memories will carry over automatically. After upgrading:

1. Set `ai_persistent_memory_llm_model_id` to enable summary generation
2. Existing memories will get their first summary on the next memory write, or you can manually trigger it by adding and removing a test memory

## How Memory Flows

```
User chats with AI
       │
       ▼
   craft_prompt()
       │
       ├─► Reads _profile_summary from PluginStore
       ├─► Injects into custom_instructions
       └─► AI now "knows" the user
       │
       ▼
   AI responds (may call memory tool)
       │
       ├─► memory.set("bible_preference", "KJV")
       │       │
       │       ├─► Saved to PluginStore
       │       ├─► Jobs.enqueue(:generate_memory_summary)
       │       └─► If count >= max: Jobs.enqueue(:consolidate_memories)
       │
       └─► memory.search("bible")
               │
               └─► Returns matching memories from PluginStore
```

## Technical Details

- **Storage**: Discourse PluginStore (PostgreSQL `plugin_store_rows` table)
- **Namespace**: `ai_user_memory_{user_id}` per user
- **System keys**: Prefixed with `_` (e.g., `_profile_summary`), hidden from user and tool
- **Prompt injection**: Prepends to `DiscourseAi::Personas::Persona#craft_prompt`
- **Tool injection**: Prepends to `DiscourseAi::Personas::ToolRunner#mini_racer_context`
- **Jobs**: `GenerateMemorySummary` (low queue), `ConsolidateMemories` (low queue)
- **Safety**: Consolidation requires ≥10 results to prevent data loss from bad LLM output

## Limitations

- Summary generation requires an LLM model to be configured
- No semantic/vector search (keyword matching only)
- Memory tool must be manually created in admin
- Consolidation overwrites without archiving
- No per-persona memory scoping (memories are per-user across all personas)

## License

MIT
