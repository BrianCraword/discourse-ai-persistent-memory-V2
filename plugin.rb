# frozen_string_literal: true

# name: discourse-ai-persistent-memory
# about: Persistent cross-conversation memory for Discourse AI personas
# version: 1.0.0
# authors: crawf
# url: https://github.com/BrianCraword/discourse-ai-persistent-memory
# required_version: 2.7.0

enabled_site_setting :ai_persistent_memory_enabled

module ::DiscourseAiPersistentMemory
  PLUGIN_NAME = "discourse-ai-persistent-memory"
end

require_relative "lib/discourse_ai_persistent_memory/engine"

after_initialize do
  require_relative "lib/discourse_ai_persistent_memory/memory_store"
  require_relative "app/controllers/discourse_ai_persistent_memory/memories_controller"
  require_relative "app/jobs/regular/generate_memory_summary"
  require_relative "app/jobs/regular/consolidate_memories"

  Discourse::Application.routes.append do
    mount DiscourseAiPersistentMemory::Engine, at: "/ai-persistent-memory"
  end

  if defined?(DiscourseAi::Personas::ToolRunner)
    require_relative "lib/discourse_ai_persistent_memory/tool_runner_extension"
    DiscourseAi::Personas::ToolRunner.prepend(DiscourseAiPersistentMemory::ToolRunnerExtension)
  end

  if defined?(DiscourseAi::Personas::Persona)
    require_relative "lib/discourse_ai_persistent_memory/persona_extension"
    DiscourseAi::Personas::Persona.prepend(DiscourseAiPersistentMemory::PersonaExtension)
  end
end
