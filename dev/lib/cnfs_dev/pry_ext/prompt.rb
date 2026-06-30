module CnfsDev
  module PryExt
    # Builds the console prompt: a Rails-env segment (green=development,
    # red=production, yellow=other) plus, when ActiveRecord::Tenanted is
    # present, a blue current-tenant segment. Renders e.g.:
    #
    #   [development][apple] cnfs(main)>
    module Prompt
      module_function

      # ANSI color helper. The \001..\002 markers tell Readline these bytes
      # are non-printing so line-editing measures the prompt width correctly.
      def color(code, text)
        "\001\e[#{code}m\002#{text}\001\e[0m\002"
      end

      # The ordered list of prompt segment procs, each returning a string
      # (possibly empty), evaluated left-to-right at render time.
      def segments
        list = [
          proc do
            env   = Rails.env.to_s
            code  = { "development" => 32, "production" => 31 }.fetch(env, 33)
            "[#{color(code, env)}]"
          end
        ]

        if defined?(ActiveRecord::Tenanted)
          list << proc do
            tenant = begin
              ApplicationRecord.current_tenant
            rescue StandardError
              nil
            end
            (tenant.nil? || tenant.to_s.empty?) ? "" : "[#{color(34, tenant)}]"
          end
        end

        list
      end

      def build(obj, nest_level, sep)
        name    = Pry.config.prompt_name || "pry"
        nesting = nest_level.zero? ? "" : ":#{nest_level}"
        rendered = segments.map(&:call).join
        "#{rendered} #{name}(#{Pry.view_clip(obj)})#{nesting}#{sep} "
      end

      # Install this prompt as the active Pry prompt.
      def install!
        Pry.config.prompt = Pry::Prompt.new(
          "cnfs_rails_env_tenant",
          "Rails.env, plus current tenant when tenanting is present",
          [
            proc { |obj, nest, _| build(obj, nest, ">") },
            proc { |obj, nest, _| build(obj, nest, "*") }
          ]
        )
      end
    end
  end
end
