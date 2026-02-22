# frozen_string_literal: true

module DiscourseAiPersistentMemory
  module PersonaExtension
    def craft_prompt(context, llm: nil)
      if SiteSetting.ai_persistent_memory_enabled && context.user.present?
        summary = DiscourseAiPersistentMemory::MemoryStore.get_summary(context.user.id)

        if summary.present?
          memory_block = <<~TEXT

            ## Persistent Memory — What you know about this user
            The following is a summary of information you have learned about this user
            from previous conversations. Use this context naturally without explicitly
            referencing that you are reading from a memory system. If the user asks
            what you remember, you may acknowledge your memory capability.

            #{summary}
          TEXT

          if context.custom_instructions.present?
            context.custom_instructions = context.custom_instructions + memory_block
          else
            context.custom_instructions = memory_block
          end
        end
      end

      super(context, llm: llm)
    end
  end
end
