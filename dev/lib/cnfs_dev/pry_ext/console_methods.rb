module CnfsDev
  module PryExt
    # Methods made available at the Pry/Rails console prompt.
    #
    # In a hand-written ~/.pryrc these would be defined as top-level methods
    # (because .pryrc is evaluated into the console's `main` object). Inside a
    # gem we instead collect them in a module and extend the console's `main`
    # binding with it (see CnfsDev::Railtie), which keeps them out of the
    # global Object namespace while preserving the same prompt ergonomics:
    #
    #   def_model_shortcuts "b", Okf::Bundle
    #   bf 3   # => Okf::Bundle.find(3), also stored in local `v`
    #
    # Everything here is guarded so it stays inert outside a Rails app.
    module ConsoleMethods
      # Reload the Rails app code (alias for Rails' reload!).
      def r
        reload! if defined?(reload!)
      end

      # Define a family of console shortcuts for a model class.
      #
      #   def_model_shortcuts "ob", Okf::Bundle  # => oba, obc, obf, obl
      #   def_model_shortcuts "b",  Okf::Bundle  # => vb, vba, vbc, vbf, vbl
      #
      # Single-character prefixes are prefixed with "v" to avoid clobbering
      # common scratch variable names (a, b, c...).
      #
      #   <prefix>    => the class itself
      #   <prefix>a   => .all
      #   <prefix>c   => .create(attributes = {})
      #   <prefix>f   => .find(id) (or .first when no id); stored in local `v`
      #   <prefix>l   => .last
      def def_model_shortcuts(prefix, klass)
        command_name = prefix
        prefix = "v#{prefix}" if prefix.length == 1

        define_console_method(prefix) { klass }
        define_console_method("#{prefix}a") { klass.all }
        define_console_method("#{prefix}c") { |attributes = {}| klass.create(attributes) }

        define_console_method("#{prefix}f") do |id = nil|
          record = id ? klass.find(id) : klass.first
          Pry.toplevel_binding.local_variable_set(:v, record)
        end

        define_console_method("#{prefix}l") { klass.last }

        Pry.config.cnfs_model_shortcut_registry << { klass: klass, command_name: command_name }
      end

      # Clear the `v` scratch local set by the `<prefix>f` shortcuts.
      def uv
        Pry.toplevel_binding.local_variable_set(:v, nil)
      end

      # --- Project reset machinery ----------------------------------------
      #
      # reset_project! re-runs db:reset + db:seed (plus any extra tasks you
      # register) from inside the console, deep-re-enabling Rake tasks so they
      # can be invoked repeatedly within a single session.

      # Extra task names appended to the default reset sequence.
      def project_reset_tasks
        @project_reset_tasks ||= []
      end

      # Register a block to run before each project reset.
      def before_project_reset(&block)
        @before_project_reset_hooks ||= []
        @before_project_reset_hooks << block if block_given?
      end

      # Re-enable a Rake task and all of its prerequisites recursively, so it
      # can be invoked more than once in the same process.
      def deep_reenable(task_or_name, scope = nil)
        task = task_or_name.is_a?(Rake::Task) ? task_or_name : Rake.application.lookup(task_or_name, scope)
        return unless task

        task.reenable
        task.prerequisites.each { |prereq_name| deep_reenable(prereq_name, task.scope) }
      end

      def reset_project!
        if defined?(@before_project_reset_hooks) && @before_project_reset_hooks&.any?
          @before_project_reset_hooks.each(&:call)
        end

        if !defined?(Rake) || Rake.application.tasks.empty?
          require "rake"
          Rails.application.load_tasks
        end

        ActiveRecord::Base.connection_handler.clear_active_connections!
        begin
          ActiveRecord::Base.connection.disconnect!
        rescue StandardError
          nil
        end

        base_tasks = %w[db:reset db:seed]
        all_tasks  = base_tasks + project_reset_tasks

        all_tasks.each do |task_name|
          deep_reenable(task_name)
          Rake::Task[task_name].invoke
        end

        ActiveRecord::Base.establish_connection
      end

      private

      # Define a method on the console's singleton (the object we've been
      # extended into), rather than globally on Object.
      def define_console_method(name, &body)
        define_singleton_method(name, &body)
      end
    end
  end
end
