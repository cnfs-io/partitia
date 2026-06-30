require_relative "pry_ext/console_methods"
require_relative "pry_ext/commands"
require_relative "pry_ext/prompt"

module CnfsDev
  # Entry point for the gem's Pry/console integration. Call
  # CnfsDev::PryExt.setup! once Pry is loaded (the Railtie does this from
  # its `console` block).
  #
  # Named PryExt (not Pry) so that unqualified `Pry` references inside this
  # namespace resolve to the real Pry gem rather than to ourselves.
  #
  # Mirrors the behavior of the original ~/.config/pry files, but namespaced
  # and opt-in so it coexists with a developer's personal ~/.pryrc rather than
  # replacing it.
  module PryExt
    module_function

    def setup!
      return unless defined?(Pry)

      Pry.config.cnfs_model_shortcut_registry ||= []

      install_step_aliases
      extend_console_methods
      Commands.install!

      return unless defined?(Rails)

      Prompt.install!
      install_boot_hook
    end

    # n/s/c/f stepping aliases, only when pry-byebug is loaded.
    def install_step_aliases
      return unless defined?(PryByebug)

      Pry.commands.alias_command "n", "next"
      Pry.commands.alias_command "s", "step"
      Pry.commands.alias_command "c", "continue"
      Pry.commands.alias_command "f", "finish"
    end

    # Mix the console helper methods into the console's `main` object at
    # session start, so they're callable bare at the prompt.
    def extend_console_methods
      Pry.config.hooks.add_hook(:when_started, :cnfs_extend_console_methods) do |_target, _options, _pry_instance|
        main = TOPLEVEL_BINDING.receiver
        main.extend(ConsoleMethods) unless main.is_a?(ConsoleMethods)
      end
    end

    # Run a one-time custom boot method if the host app defines one.
    def install_boot_hook
      Pry.config.hooks.add_hook(:before_session, :cnfs_run_once_on_boot) do |_output, _binding, _pry_instance|
        main = TOPLEVEL_BINDING.receiver
        main.custom_console_boot_method if main.respond_to?(:custom_console_boot_method)
      end
    end
  end
end
