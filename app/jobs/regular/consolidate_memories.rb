# frozen_string_literal: true

module Jobs
  class ConsolidateMemories < ::Jobs::Base
    sidekiq_options queue: "low"

    # Only one consolidation per user at a time
    cluster_concurrency 1

    def execute(args = {})
      return unless SiteSetting.ai_persistent_memory_enabled

      user_id = args[:user_id]
      return if user_id.blank?

      memories = DiscourseAiPersistentMemory::MemoryStore.list(user_id)
      max = SiteSetting.ai_persistent_memory_max_memories

      # Only consolidate if we're actually at or above the limit
      return if memories.length < max

      llm = DiscourseAiPersistentMemory::MemoryStore.resolve_llm
      unless llm
        Rails.logger.warn(
          "[discourse-ai-persistent-memory] No LLM configured for memory consolidation. " \
            "Set ai_persistent_memory_llm_model_id in site settings.",
        )
        return
      end

      user = User.find_by(id: user_id)
      return unless user

      target = SiteSetting.ai_persistent_memory_consolidation_target

      memory_text =
        memories.map { |m| "- #{m["key"]}: #{m["value"]}" }.join("\n")

      prompt =
        DiscourseAi::Completions::Prompt.new(
          <<~SYSTEM.strip,
            You are a memory consolidation assistant. Your job is to review a collection of
            memory entries about a user and produce a cleaned-up, non-redundant set.

            Rules:
            1. Merge redundant or overlapping entries into single entries.
            2. Remove clearly outdated entries if a newer entry contradicts them.
            3. Preserve all unique, important facts.
            4. Keep each memory as an atomic, distinct fact.
            5. Use clear, concise key names (snake_case, descriptive).
            6. Values should be concise but complete.
            7. Target approximately #{target} memories in the output.
            8. Respond with ONLY a valid JSON array of objects, each with "key" and "value" fields.
            9. No markdown, no explanation, no preamble — just the JSON array.
          SYSTEM
          messages: [
            {
              type: :user,
              content: <<~USER.strip,
                User: #{user.username}

                Current memory entries (#{memories.length} total, needs consolidation to ~#{target}):

                #{memory_text}

                Produce the consolidated JSON array now.
              USER
            },
          ],
        )

      begin
        result =
          llm.generate(
            prompt,
            user: Discourse.system_user,
            feature_name: "ai_persistent_memory_consolidation",
          )

        result = result.join("") if result.is_a?(Array)
        result = result.to_s.strip

        # Strip markdown code fences if present
        result = result.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "").strip

        consolidated = JSON.parse(result)

        unless consolidated.is_a?(Array)
          Rails.logger.error(
            "[discourse-ai-persistent-memory] Consolidation returned non-array for user #{user_id}",
          )
          return
        end

        # Validate structure
        consolidated =
          consolidated
            .select { |m| m.is_a?(Hash) && m["key"].present? && m["value"].present? }
            .first(SiteSetting.ai_persistent_memory_max_memories)

        if consolidated.length >= 10 # Safety: don't wipe memories if LLM returned garbage
          DiscourseAiPersistentMemory::MemoryStore.replace_all_memories(user_id, consolidated)

          # Regenerate summary after consolidation
          ::Jobs.enqueue(:generate_memory_summary, user_id: user_id)

          Rails.logger.info(
            "[discourse-ai-persistent-memory] Consolidated #{memories.length} → #{consolidated.length} memories for user #{user_id}",
          )
        else
          Rails.logger.warn(
            "[discourse-ai-persistent-memory] Consolidation produced too few results (#{consolidated.length}) for user #{user_id}. Skipping.",
          )
        end
      rescue JSON::ParserError => e
        Rails.logger.error(
          "[discourse-ai-persistent-memory] Failed to parse consolidation JSON for user #{user_id}: #{e.message}",
        )
      rescue => e
        Rails.logger.error(
          "[discourse-ai-persistent-memory] Consolidation failed for user #{user_id}: #{e.message}",
        )
      end
    end
  end
end
