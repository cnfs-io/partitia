require_relative "pry_ext/console_methods"
require_relative "pry_ext/prompt"
require_relative "pry_ext/shortcut_planner"

module Partitia
  module Dev
    # Entry point for the gem's Pry/console integration. Call
    # Partitia::Dev::PryExt.setup! once Pry is loaded (the Railtie does this from its
    # `console` block).
    #
    # Named PryExt (not Pry) so that unqualified `Pry` references inside this
    # namespace resolve to the real Pry gem rather than to ourselves.
    #
    # Design: there is exactly ONE place that touches the console `main` object —
    # the single :when_started hook installed here. Everything a consuming gem
    # contributes via Partitia::Dev.console (model namespaces, bare commands, reset
    # hooks) is drained from the Partitia::Dev registries inside that one hook, so
    # registration order is just gem load order and no gem needs its own Pry hook
    # or defensive re-extend. Prompt segments are independent of `main` and are
    # installed at setup time.
    module PryExt
      module_function

      def setup!
        return unless defined?(Pry)

        install_step_aliases if defined?(PryByebug)
        if defined?(Rails)
          drain_prompt_segments
          Prompt.install!
        end
        install_console_hook
      end

      # n/s/c/f stepping aliases, only when pry-byebug is loaded.
      def install_step_aliases
        Pry.commands.alias_command "n", "next"
        Pry.commands.alias_command "s", "step"
        Pry.commands.alias_command "c", "continue"
        Pry.commands.alias_command "f", "finish"
      end

      # Register each contributed prompt segment (stored as inert { color:, body: }
      # data on Partitia::Dev.prompt_segments) with the Prompt module, which owns the
      # ANSI/Readline handling. Done here, at console setup, so the DSL that
      # collected them never had to touch Prompt/Pry.
      def drain_prompt_segments
        Partitia::Dev.prompt_segments.each do |seg|
          Prompt.register_segment(color: seg[:color], &seg[:body])
        end
      end

      # The single hook that wires the live console `main`: mix in the console
      # methods, then drain the Partitia::Dev registries (namespaces + bare commands +
      # reset hooks) contributed by partitia-dev itself and any consuming gem.
      def install_console_hook
        Pry.config.hooks.add_hook(:when_started, :partitia_console) do |_target, _options, _pry_instance|
          main = TOPLEVEL_BINDING.receiver
          main.extend(ConsoleMethods) unless main.is_a?(ConsoleMethods)
          main.install_reload_memo_clear! if defined?(Rails)

          # Models must be loaded before the planner can enumerate namespace
          # descendants; the dev console does not eager-load by default.
          Rails.application.eager_load! if defined?(Rails) && Rails.respond_to?(:application)

          ShortcutPlanner.plan(Partitia::Dev.namespaces, models: Partitia::Dev.models).each do |s|
            main.def_model_shortcuts(s[:prefix], s[:klass])
          end

          Partitia::Dev.commands.each do |cmd|
            main.define_singleton_method(cmd[:name], &cmd[:body])
          end

          Partitia::Dev.before_resets.each do |body|
            main.before_project_reset(&body)
          end

          Partitia::Dev.reset_tasks.each do |task_name|
            main.project_reset_tasks << task_name
          end
        end
      end
    end
  end
end
