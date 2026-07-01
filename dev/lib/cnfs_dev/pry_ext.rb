require_relative "pry_ext/console_methods"
require_relative "pry_ext/prompt"
require_relative "pry_ext/builder"

module CnfsDev
  # Entry point for the gem's Pry/console integration. Call
  # CnfsDev::PryExt.setup! once Pry is loaded (the Railtie does this from its
  # `console` block).
  #
  # Named PryExt (not Pry) so that unqualified `Pry` references inside this
  # namespace resolve to the real Pry gem rather than to ourselves.
  #
  # Design: there is exactly ONE place that touches the console `main` object —
  # the single :when_started hook installed here. Everything a consuming gem
  # contributes via CnfsDev.console (model shortcuts, bare commands) is drained
  # from the Builder registries inside that one hook, so registration order is
  # just gem load order and no gem needs its own Pry hook or defensive
  # re-extend. Prompt segments are independent of `main` and are installed at
  # setup time.
  module PryExt
    module_function

    def setup!
      return unless defined?(Pry)

      install_step_aliases if defined?(PryByebug)
      Prompt.install! if defined?(Rails)
      install_console_hook
    end

    # n/s/c/f stepping aliases, only when pry-byebug is loaded.
    def install_step_aliases
      Pry.commands.alias_command "n", "next"
      Pry.commands.alias_command "s", "step"
      Pry.commands.alias_command "c", "continue"
      Pry.commands.alias_command "f", "finish"
    end

    # The single hook that wires the live console `main`: mix in the console
    # methods, then drain the Builder registries (shortcuts + bare commands)
    # contributed by cnfs_dev itself and any consuming gem.
    def install_console_hook
      Pry.config.hooks.add_hook(:when_started, :cnfs_console) do |_target, _options, _pry_instance|
        main = TOPLEVEL_BINDING.receiver
        main.extend(ConsoleMethods) unless main.is_a?(ConsoleMethods)

        Builder.shortcuts.each do |s|
          main.def_model_shortcuts(s[:prefix], s[:klass])
        end

        Builder.commands.each do |cmd|
          main.define_singleton_method(cmd[:name], &cmd[:body])
        end

        Builder.before_resets.each do |body|
          main.before_project_reset(&body)
        end

        Builder.reset_tasks.each do |task_name|
          main.project_reset_tasks << task_name
        end
      end
    end
  end
end
