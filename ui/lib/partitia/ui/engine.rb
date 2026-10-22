require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"
require "phlex-rails"


module Partitia
  module Ui
    class Engine < ::Rails::Engine
      isolate_namespace Partitia::Ui

      config.generators do |g|
        g.template_engine :tailwindcss
      end
    end
  end
end
