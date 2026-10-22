require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"
require "phlex-rails"


module CnfsUi
  class Engine < ::Rails::Engine
    isolate_namespace CnfsUi

    config.generators do |g|
      g.template_engine :tailwindcss
    end
  end
end
