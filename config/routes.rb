# frozen_string_literal: true

DiscourseAiPersistentMemory::Engine.routes.draw do
  get "/" => "memories#index"
  post "/" => "memories#create"
  delete "/:key" => "memories#destroy", constraints: { key: /[^\/]+/ }
end
