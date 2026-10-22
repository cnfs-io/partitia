module Partitia
  module Support
    module Generators
      # Line-based, structure-aware reading of a host's config/database.yml: finds,
      # for each environment, where the primary database's `migrations_paths:` line
      # belongs. It never parses the YAML (that would lose comments and ERB) and
      # never writes; the install generator injects at the points it returns.
      #
      # Understands the two shapes `rails new` emits:
      #
      #   development:              production:
      #     <<: *default              primary:
      #     database: app_dev           <<: *default
      #                                 database: app_prod
      #                               cache: ...
      #
      # A flat environment is the primary database; in a multi-database one only
      # `primary:` is wired. The line goes after `database:` (or `url:`), at its
      # indent; failing both, after the block's last key (a commented-out database).
      #
      # Pure Ruby (no Rails), so it is unit-tested in the Rails-free suite.
      class DatabaseYml
        LINE = "migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>".freeze

        # status: :inject (line_index, indent set), :present, or :manual (message set)
        Point = Struct.new(:env, :status, :line_index, :indent, :message, keyword_init: true)

        ANCHOR_KEYS = %w[database url].freeze
        # Keys that mark an environment block as a single (flat) database.
        FLAT_KEYS = %w[database url adapter <<].freeze

        def initialize(content)
          @lines = content.lines
        end

        def points(envs) = envs.map { |env| point_for(env.to_s) }

        private

        attr_reader :lines

        def point_for(env)
          env_index = key_index(env, 0, lines.size, 0)
          return manual(env, "no `#{env}:` block found") unless env_index
          # Already reading the registry for some scope (partitia-tenanted's global and
          # tenant planes, which have no primary): wired by whoever wrote it
          return Point.new(env:, status: :present) if registry?(env_index + 1, block_end(env_index, 0))

          target = block_target(env, env_index)
          return target if target.is_a?(Point)

          start, stop, label = target
          indent = child_indent(start, stop)
          return manual(env, "`#{label}:` is empty") unless indent

          existing = key_index("migrations_paths", start, stop, indent)
          if existing
            return Point.new(env:, status: :present) if lines[existing].include?(LINE.split(": ", 2).last)

            return manual(env, "`#{label}:` already sets migrations_paths (line #{existing + 1}); " \
                               "add the partitia paths to it")
          end

          anchor = ANCHOR_KEYS.lazy.map { |key| key_index(key, start, stop, indent) }.find(&:itself) ||
                   (start...stop).select { |i| content?(lines[i]) && indent_of(lines[i]) == indent }.last

          Point.new(env:, status: :inject, line_index: anchor, indent: " " * indent)
        end

        # The range of lines holding the primary database's keys for +env+:
        # [start, stop, label], or a :manual Point.
        def block_target(env, env_index)
          start = env_index + 1
          stop = block_end(env_index, 0)
          indent = child_indent(start, stop)
          return manual(env, "`#{env}:` is empty") unless indent

          primary = key_index("primary", start, stop, indent)
          return [ primary + 1, block_end(primary, indent), "#{env}: primary" ] if primary
          return [ start, stop, env ] if FLAT_KEYS.any? { |key| key_index(key, start, stop, indent) }

          manual(env, "`#{env}:` is neither a single database (no `database:`/`adapter:`/`<<:`) " \
                      "nor a multi-database block with `primary:`")
        end

        # Index of the first `key:` line at exactly +indent+ within [start, stop).
        def key_index(key, start, stop, indent)
          pattern = /\A {#{indent}}#{Regexp.escape(key)}:(\s|\z)/
          (start...stop).find { |i| lines[i].match?(pattern) }
        end

        # Indent of the first content line in [start, stop), or nil.
        def child_indent(start, stop)
          i = (start...stop).find { |n| content?(lines[n]) }
          i && indent_of(lines[i])
        end

        # The first line after +index+ that is content at or left of +indent+.
        def block_end(index, indent)
          ((index + 1)...lines.size).find { |i| content?(lines[i]) && indent_of(lines[i]) <= indent } || lines.size
        end

        def registry?(start, stop)
          (start...stop).any? { |i| content?(lines[i]) && lines[i].include?("Partitia::Support.migrations_paths[") }
        end

        def content?(line) = !line.strip.empty? && !line.lstrip.start_with?("#")

        def indent_of(line) = line[/\A */].size

        def manual(env, why)
          Point.new(env:, status: :manual,
                    message: "#{why}. Add `#{LINE}` to the primary database of `#{env}:`, " \
                             "at the indent of its `database:` line.")
        end
      end
    end
  end
end
