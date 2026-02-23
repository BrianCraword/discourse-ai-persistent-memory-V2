# frozen_string_literal: true

module DiscourseAiPersistentMemory
  class MemoryStore
    SUMMARY_KEY = "_profile_summary"
    SYSTEM_KEY_PREFIX = "_"

    def self.namespace(user_id)
      "ai_user_memory_#{user_id}"
    end

    def self.set(user_id, key, value)
      return { error: "no_user" } unless user_id
      return { error: "key_required" } if key.blank?
      return { error: "system_key" } if key.to_s.start_with?(SYSTEM_KEY_PREFIX)

      max_length = SiteSetting.ai_persistent_memory_max_value_length
      value = value.to_s[0...max_length]

      count = memory_count(user_id)
      existing = PluginStore.get(namespace(user_id), key.to_s)
      max = SiteSetting.ai_persistent_memory_max_memories

      if existing.nil? && count >= max
        return { error: "limit_reached", max: max }
      end

      PluginStore.set(namespace(user_id), key.to_s, value)
      schedule_summary_regeneration(user_id)
      maybe_consolidate(user_id)

      { success: true, key: key, value: value }
    end

    def self.get(user_id, key)
      return nil unless user_id
      PluginStore.get(namespace(user_id), key.to_s)
    end

    def self.list(user_id)
      return [] unless user_id
      PluginStoreRow
        .where(plugin_name: namespace(user_id))
        .where.not("key LIKE ?", "\\_%" )
        .pluck(:key, :value)
        .map { |k, v| { "key" => k, "value" => v } }
    end

    def self.delete(user_id, key)
      return { error: "no_user" } unless user_id
      return { error: "system_key" } if key.to_s.start_with?(SYSTEM_KEY_PREFIX)

      PluginStore.remove(namespace(user_id), key.to_s)
      schedule_summary_regeneration(user_id)

      { success: true }
    end

    def self.memory_count(user_id)
      PluginStoreRow
        .where(plugin_name: namespace(user_id))
        .where.not("key LIKE ?", "\\_%" )
        .count
    end

    def self.get_summary(user_id)
      return nil unless user_id
      PluginStore.get(namespace(user_id), SUMMARY_KEY)
    end

    def self.set_summary(user_id, summary)
      PluginStore.set(namespace(user_id), SUMMARY_KEY, summary)
    end

    def self.clear_summary(user_id)
      PluginStore.remove(namespace(user_id), SUMMARY_KEY)
    end

    def self.replace_all_memories(user_id, memories)
      ns = namespace(user_id)

      # Remove all non-system keys
      PluginStoreRow
        .where(plugin_name: ns)
        .where.not("key LIKE ?", "\\_%" )
        .delete_all

      # Write consolidated memories
      memories.each do |mem|
        key = mem["key"] || mem[:key]
        value = mem["value"] || mem[:value]
        next if key.blank? || key.to_s.start_with?(SYSTEM_KEY_PREFIX)
        PluginStore.set(ns, key.to_s, value.to_s[0...SiteSetting.ai_persistent_memory_max_value_length])
      end
    end

    def self.resolve_llm
      model_id = SiteSetting.ai_persistent_memory_llm_model_id
      return nil if model_id.blank?

      llm_model = LlmModel.find_by(id: model_id.to_i)
      return nil unless llm_model

      DiscourseAi::Completions::Llm.proxy(llm_model)
    end

    private

    def self.schedule_summary_regeneration(user_id)
      ::Jobs.enqueue(:generate_memory_summary, user_id: user_id)
    end

    def self.maybe_consolidate(user_id)
      count = memory_count(user_id)
      max = SiteSetting.ai_persistent_memory_max_memories

      if count >= max
        ::Jobs.enqueue(:consolidate_memories, user_id: user_id)
      end
    end
  end
end
