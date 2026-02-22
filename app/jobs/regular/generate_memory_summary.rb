# frozen_string_literal: true

module Jobs
  class GenerateMemorySummary < ::Jobs::Base
    sidekiq_options queue: "low"

    # Debounce: if multiple memory writes happen in quick succession,
    # only the last job actually runs the LLM call.
    cluster_concurrency 1

    def execute(args = {})
      return unless SiteSetting.ai_persistent_memory_enabled

      user_id = args[:user_id]
      return if user_id.blank?

      memories = DiscourseAiPersistentMemory::MemoryStore.list(user_id)

      if memories.empty?
        DiscourseAiPersistentMemory::MemoryStore.clear_summary(user_id)
        return
      end

      llm = DiscourseAiPersistentMemory::MemoryStore.resolve_llm
      unless llm
        Rails.logger.warn(
          "[discourse-ai-persistent-memory] No LLM configured for memory summarization. " \
            "Set ai_persistent_memory_llm_model_id in site settings.",
        )
        return
      end

      user = User.find_by(id: user_id)
      return unless user

      memory_text =
        memories.map { |m| "- #{m["key"]}: #{m["value"]}" }.join("\n")

      prompt =
        DiscourseAi::Completions::Prompt.new(
          <<~SYSTEM.strip,
            You are a concise profile summarizer. Given a list of memory entries about a user,
            write a single paragraph (maximum 200 words) that captures the most important facts
            an AI assistant should know about this person. Focus on: preferences, expertise,
            current projects, communication style, and relevant personal context.

            Write in third person using the user's name if available, otherwise say "This user".
            Be factual and concise. Do not add speculation or filler. Do not use bullet points
            or lists — write flowing prose. Do not mention that you are summarizing memories.
          SYSTEM
          messages: [
            {
              type: :user,
              content: <<~USER.strip,
                User: #{user.username}

                Memory entries:
                #{memory_text}

                Write the profile summary paragraph now.
              USER
            },
          ],
        )

      begin
        summary =
          llm.generate(
            prompt,
            user: Discourse.system_user,
            feature_name: "ai_persistent_memory_summary",
          )

        # Handle array responses (some models return structured output)
        summary = summary.join("") if summary.is_a?(Array)
        summary = summary.to_s.strip

        if summary.present? && summary.length > 20
          DiscourseAiPersistentMemory::MemoryStore.set_summary(user_id, summary)
        end
      rescue => e
        Rails.logger.error(
          "[discourse-ai-persistent-memory] Summary generation failed for user #{user_id}: #{e.message}",
        )
      end
    end
  end
end
