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
    #   bf 3   # => Okf::Bundle.find(3), memoized for repeat calls
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
      #   <prefix>a   => .all (never memoized)
      #   <prefix>c   => .create(attributes = {}); on success it busts the
      #                  <prefix>l memo so the next <prefix>l returns the new row
      #   <prefix>f   => .find(id) (or .first when no id); memoized per id
      #   <prefix>l   => .last; memoized
      #
      # The memoized readers (<prefix>f, <prefix>l) return the same object on
      # repeat calls with no query. Append "!" to force a refresh (<prefix>f!,
      # <prefix>l!), and use `uv` to clear memos.
      def def_model_shortcuts(prefix, klass)
        prefix = "v#{prefix}" if prefix.length == 1

        define_console_method(prefix) { klass }
        define_console_method("#{prefix}a") { klass.all }

        define_console_method("#{prefix}c") do |attributes = {}|
          record = klass.create(attributes)
          shortcut_memo.delete_if { |k, _| k.first == :"#{prefix}l" } if record.persisted?
          record
        end

        define_memoized_console_method("#{prefix}f") { |id = nil| id ? klass.find(id) : klass.first }
        define_memoized_console_method("#{prefix}l") { klass.last }
      end

      # Clear memoized shortcut records. `uv` clears everything; `uv :vtf`
      # clears the memos for one shortcut family.
      def uv(name = nil)
        name ? shortcut_memo.delete_if { |k, _| k.first == name.to_sym } : shortcut_memo.clear
        nil
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
        shortcut_memo.clear

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

      # Per-session store for memoized shortcut records, keyed by
      # [shortcut_name, *args]. Lives on the console `main` object.
      def shortcut_memo
        @shortcut_memo ||= {}
      end

      # Define a memoized reader plus a "!" force-refresh twin from one fetch
      # block. The reader returns the cached record on repeat calls (keyed by
      # its args); the bang always fetches and overwrites the memo.
      def define_memoized_console_method(name, &fetch)
        key = name.to_sym

        define_console_method(name) do |*args|
          memo = shortcut_memo
          memo.key?([key, *args]) ? memo[[key, *args]] : (memo[[key, *args]] = fetch.call(*args))
        end

        define_console_method("#{name}!") do |*args|
          shortcut_memo[[key, *args]] = fetch.call(*args)
        end
      end

      # Define a method on the console's singleton (the object we've been
      # extended into), rather than globally on Object.
      def define_console_method(name, &body)
        define_singleton_method(name, &body)
      end
    end
  end
end
