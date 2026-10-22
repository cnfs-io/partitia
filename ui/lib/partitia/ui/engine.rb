require "partitia/support"
require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"
require "phlex-rails"

module Partitia
  module Ui
    class Engine < ::Rails::Engine
      isolate_namespace Partitia::Ui

      # Register with partitia-support so app/components and app/views reach the host's
      # Tailwind sources (Partitia::Support.source_paths). ARCHITECTURE §3, Q6.
      Partitia::Support.plugins << self

      config.generators do |g|
        g.template_engine :tailwindcss
      end
    end
  end
end
