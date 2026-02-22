# frozen_string_literal: true

module DiscourseAiPersistentMemory
  class MemoriesController < ::ApplicationController
    requires_plugin DiscourseAiPersistentMemory::PLUGIN_NAME
    requires_login

    def index
      memories = MemoryStore.list(current_user.id)
      summary = MemoryStore.get_summary(current_user.id)
      count = memories.length
      max = SiteSetting.ai_persistent_memory_max_memories

      render json: {
        memories: memories,
        summary: summary,
        count: count,
        max: max,
      }
    end

    def create
      key = params.require(:key).to_s.strip
      value = params.require(:value).to_s.strip

      result = MemoryStore.set(current_user.id, key, value)

      if result[:error]
        render json: { error: result[:error] }, status: 422
      else
        render json: result
      end
    end

    def destroy
      key = params[:key]
      return render json: { error: "Key required" }, status: 400 if key.blank?

      result = MemoryStore.delete(current_user.id, key)

      if result[:error]
        render json: { error: result[:error] }, status: 422
      else
        head :no_content
      end
    end
  end
end
