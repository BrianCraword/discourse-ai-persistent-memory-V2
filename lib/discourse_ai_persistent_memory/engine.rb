# frozen_string_literal: true

module DiscourseAiPersistentMemory
  class Engine < ::Rails::Engine
    engine_name DiscourseAiPersistentMemory::PLUGIN_NAME
    isolate_namespace DiscourseAiPersistentMemory
  end
end
