require "rails/generators/base"
require_relative "database_yml"

module Partitia
  module Support
    module Generators
      # Wires a host app's database.yml to pull migrations from every registered
      # partitia-* engine:
      #
      #   rails g partitia:support:install
      #
      # For each of development, test and production it injects
      #
      #   migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>
      #
      # into the primary database (the flat environment block, or its `primary:`
      # in a multi-database block), right after its `database:` line. The value is
      # ERB evaluated when Rails loads database.yml, so the paths track whatever
      # engines are registered at boot.
      #
      # Idempotent: an environment already wired is left alone. Where it cannot
      # tell where the line goes, it changes nothing there and says what to add.
      # Falls back to spec/dummy/config/database.yml inside an engine.
      class InstallGenerator < Rails::Generators::Base
        ENVIRONMENTS = %w[development test production].freeze
        DB_FILE = "config/database.yml".freeze

        desc "Point config/database.yml at the partitia-* aggregated migrations_paths, in every environment."

        def add_migrations_paths
          @todo = []
          path = database_yml_path
          unless path
            say_status :skip, "#{DB_FILE} not found", :yellow
            @todo << "Create #{DB_FILE} and add `#{DatabaseYml::LINE}` to the primary database of " \
                     "#{ENVIRONMENTS.join(', ')}."
            return
          end

          content = File.read(path)
          points = DatabaseYml.new(content).points(ENVIRONMENTS)
          points.each { |point| report(point) }
          inject(path, content, points.select { |point| point.status == :inject })
        end

        def print_next_steps
          if @todo.empty?
            say "partitia-support: database.yml is wired; nothing left to do.", :green
          else
            say "partitia-support: the host still has to:", :yellow
            @todo.each { |step| say "  - #{step}" }
          end
        end

        private

        def database_yml_path
          root = Pathname.new(destination_root)
          [ root.join(DB_FILE), root.join("spec/dummy", DB_FILE) ].find(&:exist?)&.to_s
        end

        def report(point)
          case point.status
          when :present then say_status :identical, "migrations_paths (#{point.env})", :blue
          when :manual
            say_status :manual, "#{point.env}: #{point.message}", :yellow
            @todo << "#{DB_FILE} (#{point.env}): #{point.message}"
          end
        end

        # Bottom-up, each anchored on the file's exact prefix up to the target
        # line, so the match is unique and earlier insertions don't shift later ones.
        # `force:` here only lets Thor insert the same line a second time (it skips
        # text already present anywhere in the file); idempotence is DatabaseYml's
        # per-environment :present check. The file itself is never rewritten.
        def inject(path, content, points)
          lines = content.lines
          points.sort_by(&:line_index).reverse_each do |point|
            prefix = lines[0..point.line_index].join
            line = "#{point.indent}#{DatabaseYml::LINE}"
            text = prefix.end_with?("\n") ? "#{line}\n" : "\n#{line}"
            insert_into_file path, text, after: /\A#{Regexp.escape(prefix)}/, force: true
          end
        end
      end
    end
  end
end
