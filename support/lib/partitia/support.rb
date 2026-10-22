require_relative "support/version"
require_relative "support/config"
require_relative "support/redaction_config"
require_relative "support/urn_config"
require_relative "support/logging"
require_relative "support/instrumentable"
require_relative "support/shell"
require_relative "support/storable"
require_relative "support/railtie" if defined?(Rails::Railtie)
require "active_support/core_ext/string/inflections"

# Partitia::Support is the lean foundation gem for the CNFS family — the active_support
# analogue. It carries dependency-light primitives that other CNFS gems and the
# apps can depend on freely, in any environment.
module Partitia
  module Support
    # Derive a component tag from a fully-qualified class/module name: the first
    # `::`-split segment, underscored and partitia-prefixed. A Partitia engine's
    # constants are tagged by their engine segment. `"Okf::Button"` =>
    # `"partitia_okf"`; `"Partitia::Cognito::Session"` => `"partitia_cognito"` (an
    # already-prefixed segment is left as-is). Anonymous or nameless classes (name
    # nil or empty), and the bare `Partitia` module, fall back to `"partitia"`.
    #
    # The Logging mixin keys off this rule for its tag. Telemetry (in the separate
    # partitia-telemetry gem) derives the same rule from notification names, so a gem's
    # log tags and trace instrumentation-library names stay aligned.
    def self.component_tag(name)
      segments = name.to_s.split("::")
      segments.shift if segments.first == "Partitia" && segments.size > 1
      segment = segments.first&.underscore
      return "partitia" if segment.nil? || segment.empty? || segment == "partitia"

      segment.start_with?("partitia_") ? segment : "partitia_#{segment}"
    end

    # Any rails plugin can register here
    # Any migrations or global migrations will be registered here
    def self.plugins
      @plugins ||= Set.new
    end

    # Yields Rails (the host app) followed by every registered plugin engine.
    # The host is yielded FIRST so its paths take precedence in any ordered
    # collection.
    #
    # THE single place the "Rails + plugins, with the Engine guard" walk is
    # expressed. Every path-collection initializer (migrations, Tailwind sources,
    # and whatever comes next) invokes this rather than re-implementing the loop —
    # so a change to what counts as a plugin, or to the ordering, lands once.
    #
    # `Rails` itself is not an Engine (it is a module), which is why the guard
    # applies only to members of `plugins`. Both respond to `.root`, which is all a
    # collector needs.
    def self.each_plugin
      return enum_for(:each_plugin) unless block_given?

      yield Rails
      plugins.each do |plugin|
        raise "#{plugin} must be a Rails Engine" unless plugin.is_a?(Class) && plugin < ::Rails::Engine

        yield plugin
      end
    end

    # There are two ways migrations paths are set
    # 1. The application's database.yml DOES NOT declare migrations_paths for a database (default)
    #    In this case Rails will apply the value of app.config.paths['db/migrate']
    #
    # 2. The application's database.yml declares migrations_paths for a database
    #    In that case it can either
    #    1. Hard code it
    #         migrations_paths = ["path/1", "path/2"]
    #    2. Use Partitia::Support's migrations_paths, addressed by scope key:
    #         migrations_paths = <%= Partitia::Support.migrations_paths[:some_scope] %>
    #
    # Partitia::Support migrations_paths will include paths to all engine's migrations paths
    #   so it is assumed that when using this in database.yml that you are NOT copying
    #   migrations from engines into the app.
    # If the desired workflow is to copy from engines then just hardcode the migrations_paths
    #   or don't declare it and Rails will work as per default
    def self.migrations_paths_for
      @migrations_paths_for ||= { primary: "db/migrate" }
    end

    def self.migrations_paths
      @migrations_paths ||= {}
    end

    def self.set_migrations_paths_from(plugin)
      migrations_paths_for.each do |key, search_path|
        migrations_paths[key] ||= []

        path = plugin.root.join(search_path)
        next unless path.exist?

        path = path.to_s
        migrations_paths[key] << path unless migrations_paths[key].include?(path)
      end
    end

    # Directories within a plugin that Tailwind must scan for utility classes.
    # NOTE: today OKF's Tailwind-classed markup lives under app/views (scaffold
    # output). When a dedicated UI gem ships Phlex components they will live under
    # app/components in THAT gem — which, being a registered plugin, contributes its
    # own app/components automatically through this same list. So app/components is
    # included here now even though OKF itself may not use it yet.
    def self.source_paths_for
      @source_paths_for ||= %w[app/views app/helpers app/components]
    end

    # Absolute paths to every registered plugin's Tailwind-scannable dirs.
    # Consumed from a Tailwind entry CSS (application.css.erb):
    #
    #   <% Partitia::Support.source_paths.each do |path| %>
    #   @source "<%= path %>";
    #   <% end %>
    #
    # Absolute (not relative) by design: a relative `@source` must be counted from
    # the entry file's location, which is brittle across engines — see the
    # five-levels-up comment this replaces.
    def self.source_paths
      @source_paths ||= []
    end

    def self.set_source_paths_from(plugin)
      source_paths_for.each do |dir|
        path = plugin.root.join(dir)
        next unless path.exist?

        path = path.to_s
        source_paths << path unless source_paths.include?(path)
      end
    end

    def self.migrations
      migrations_paths.each_with_object([]) do |(key, paths), ary|
        paths.each do |path|
          path = Pathname.new(path)
          ary.concat(path.children.collect(&:to_s)) if path.exist?
        end
      end
    end
  end
end
