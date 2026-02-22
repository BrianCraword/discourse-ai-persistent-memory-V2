# frozen_string_literal: true

module DiscourseAiPersistentMemory
  module ToolRunnerExtension
    MEMORY_JS = <<~JS
      const memory = {
        set: function(key, value) {
          const result = _memory_set(key, typeof value === 'object' ? JSON.stringify(value) : String(value));
          if (result && result.error) throw new Error(result.error);
          return result;
        },
        get: function(key) {
          const result = _memory_get(key);
          if (!result) return null;
          try { return JSON.parse(result); } catch(e) { return result; }
        },
        list: function() { return _memory_list(); },
        delete: function(key) {
          const result = _memory_delete(key);
          if (result && result.error) throw new Error(result.error);
          return result;
        },
        search: function(query) { return _memory_search(query); }
      };
    JS

    def mini_racer_context
      @mini_racer_context ||=
        begin
          ctx = super
          attach_memory(ctx)
          ctx
        end
    end

    def framework_script
      super + "\n" + MEMORY_JS
    end

    private

    def attach_memory(mini_racer_context)
      mini_racer_context.attach(
        "_memory_set",
        ->(key, value) do
          in_attached_function do
            user_id = @context.user&.id
            return { error: "No user context" } unless user_id

            result = DiscourseAiPersistentMemory::MemoryStore.set(user_id, key, value)
            result
          end
        end,
      )

      mini_racer_context.attach(
        "_memory_get",
        ->(key) do
          in_attached_function do
            user_id = @context.user&.id
            return nil unless user_id

            DiscourseAiPersistentMemory::MemoryStore.get(user_id, key)
          end
        end,
      )

      mini_racer_context.attach(
        "_memory_list",
        ->() do
          in_attached_function do
            user_id = @context.user&.id
            return [] unless user_id

            DiscourseAiPersistentMemory::MemoryStore.list(user_id)
          end
        end,
      )

      mini_racer_context.attach(
        "_memory_delete",
        ->(key) do
          in_attached_function do
            user_id = @context.user&.id
            return { error: "No user context" } unless user_id

            DiscourseAiPersistentMemory::MemoryStore.delete(user_id, key)
          end
        end,
      )

      mini_racer_context.attach(
        "_memory_search",
        ->(query) do
          in_attached_function do
            user_id = @context.user&.id
            return [] unless user_id
            return [] if query.blank?

            query_lower = query.to_s.downcase
            terms = query_lower.split(/\s+/)

            DiscourseAiPersistentMemory::MemoryStore
              .list(user_id)
              .select do |mem|
                searchable = "#{mem["key"]} #{mem["value"]}".downcase
                terms.any? { |term| searchable.include?(term) }
              end
              .first(10)
          end
        end,
      )
    end
  end
end
