# frozen_string_literal: true

require "rails/engine"

module PocketPhone
  class Engine < ::Rails::Engine
    isolate_namespace PocketPhone
  end
end
