require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"

module Chatter
  class Engine < ::Rails::Engine
    isolate_namespace Chatter
    CnfsSupport.plugins << self

    config.generators do |g|
      g.template_engine :tailwindcss
    end

    # Serve the engine's JS and feed its pins into the host importmap.
    initializer "chatter.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    initializer "chatter.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end
  end
end
