module CnfsDev
  module PryExt
    # Generates `cd<name>` navigation commands that switch the Pry context
    # into a registered class (e.g. `cdr` => `cd Rails`), and registers the
    # tenant switch helper when ActiveRecord::Tenanted is present.
    #
    # The registry lives on Pry.config.cnfs_model_shortcut_registry so it is
    # namespaced away from any registry a personal ~/.pryrc may define.
    module Commands
      module_function

      # Seed the registry with Rails itself and install the before_session
      # hook that turns each registry entry into a `cd<command_name>` command.
      def install!
        Pry.config.cnfs_model_shortcut_registry ||= []

        if defined?(Rails) && Pry.config.cnfs_model_shortcut_registry.none? { |s| s[:command_name] == "r" }
          Pry.config.cnfs_model_shortcut_registry << { klass: Rails, command_name: "r" }
        end

        Pry.config.hooks.add_hook(:before_session, :cnfs_generate_navigation_commands) do |_output, _binding, pry_instance|
          custom_commands = Pry::CommandSet.new do
            Pry.config.cnfs_model_shortcut_registry.each do |shortcut|
              command "cd#{shortcut[:command_name]}", "Switch Pry context into #{shortcut[:klass]}" do
                pry_instance.run_command("cd #{shortcut[:klass]}")
              end
            end
          end

          pry_instance.commands.import(custom_commands)
        end
      end
    end
  end
end
