require "rails/generators/base"

module Partitia
  module Support
    module Generators
      # Wires a host app's database.yml to pull migrations from every mounted
      # partitia-* engine:
      #
      #   rails g partitia:support:install
      #
      #   - injects `migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>`
      #     into config/database.yml, right after the primary `database:` line.
      #
      # The injected value is an ERB expression evaluated when Rails loads
      # database.yml, so the resolved paths track whatever engines are mounted at
      # boot (see Partitia::Support.set_migrations_paths_from).
      class InstallGenerator < Rails::Generators::Base
        attr_accessor :cwd

        DATABASE_LINE = /^(\s*)database: storage\/development\.sqlite3\n/

        desc "Point config/database.yml at the partitia-* aggregated migrations_paths."

        def add_migrations_paths
          cwd = Pathname.new(destination_root)
          cwd = cwd.join("spec/dummy") unless cwd.join(db_file_name).exist?
          db_file = cwd.join(db_file_name)

          # line = "database: storage/development.sqlite3"
          inject = "migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>"

          unless db_file.exist?
            say_status :skip, "config/database.yml not found", :yellow
            return
          end

          # if File.read("config/database.yml").include?(inject)
          if db_file.read.include?(inject)
            say_status :skip, "migrations_paths already set", :blue
            return
          end

          # inject_into_file "config/database.yml", after: DATABASE_LINE do
          inject_into_file db_file.to_s, after: DATABASE_LINE do
            indent_of(db_file, DATABASE_LINE) + inject + "\n"
          end
        end

        private

        def db_file_name = "config/database.yml"

        # Match the injection line's indentation to the `database:` line it follows,
        # so the emitted YAML stays well-formed.
        def indent_of(db_config, pattern)
          # File.read("config/database.yml")[pattern, 1] || "  "
          db_config.read[pattern, 1] || "  "
        end
      end
    end
  end
end
