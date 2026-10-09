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
    #   def_model_shortcuts "ob", Okf::Bundle
    #   obf 3   # => Okf::Bundle.find(3), memoized for repeat calls
    #
    # Prefixes come from ShortcutPlanner (namespace letter + model code), so
    # they are always at least two characters and never collide with common
    # single-letter scratch variables.
    #
    # Everything here is guarded so it stays inert outside a Rails app.
    module ConsoleMethods
      # Reload the Rails app code (alias for Rails' reload!).
      def r
        reload! if defined?(reload!)
      end

      def log!
        ActiveRecord::Base.logger = ActiveRecord::Base.logger.nil? ? Rails.logger : nil
        log
      end

      def log = "Rails logger #{ActiveRecord::Base.logger.nil? ? "OFF" : "ON"}"

      # Define a family of console shortcuts for a model class.
      #
      #   def_model_shortcuts "ob", Okf::Bundle  # => ob, oba, obc, obf, obl, obp
      #
      #   <prefix>    => the class itself
      #   <prefix>a   => .all (never memoized)
      #   <prefix>c   => .create(attributes = {}); on success it busts the
      #                  <prefix>l memo so the next <prefix>l returns the new row
      #   <prefix>f   => .find(id) (or .first when no id); memoized per id
      #   <prefix>l   => .last; memoized
      #   <prefix>p   => .all.pluck(*args); same signature as pluck
      #                  (e.g. obp :name, :age => Okf::Bundle.all.pluck(:name, :age))
      #
      # The memoized readers (<prefix>f, <prefix>l) return the same object on
      # repeat calls with no query. Append "!" to force a refresh (<prefix>f!,
      # <prefix>l!), and use `clear!` to clear memos.
      def def_model_shortcuts(prefix, klass)
        register_shortcut(prefix, klass)

        define_console_method(prefix) { klass }
        define_console_method("#{prefix}a") { klass.all }
        define_console_method("#{prefix}p") { |*args| klass.all.pluck(*args) }

        define_console_method("#{prefix}c") do |attributes = {}|
          record = klass.create(attributes)
          shortcut_memo.delete_if { |k, _| k.first == :"#{prefix}l" } if record.persisted?
          record
        end

        define_memoized_console_method("#{prefix}f") { |id = nil| id ? klass.find(id) : klass.first }
        define_memoized_console_method("#{prefix}l") { klass.last }
      end

      # List the registered model shortcut families, optionally filtered to
      # those whose prefix starts with `match`:
      #
      #   shortcuts        # => every family
      #   shortcuts "c"    # => families whose prefix starts with "c"
      #   shortcuts "ca"   # => families whose prefix starts with "ca"
      #
      # Returns a Hash of prefix => class, and prints an aligned table.
      def shortcuts(match = nil)
        pairs = shortcut_registry.select { |prefix, _| match.nil? || prefix.start_with?(match.to_s) }
                                 .sort_by { |prefix, _| prefix }

        width = pairs.map { |prefix, _| prefix.length }.max || 0
        pairs.each { |prefix, klass| puts "#{prefix.ljust(width)}  #{klass}" }

        nil
      end

      # Clear memoized shortcut records. `clear!` clears everything; `clear! :obf`
      # clears the memos for one shortcut family.
      def clear!(name = nil)
        name ? shortcut_memo.delete_if { |k, _| k.first == name.to_sym } : shortcut_memo.clear
        nil
      end

      # Wrap the console's `reload!` so reloading application code also clears
      # every memo — the reloaded classes make cached instances stale. Prepends
      # onto the singleton so `super` reaches the real reload! regardless of how
      # Rails defined it. Idempotent; only meaningful in a Rails console.
      def install_reload_memo_clear!
        return if @reload_memo_clear_installed

        @reload_memo_clear_installed = true
        singleton_class.prepend(Module.new do
          def reload!(*)
            shortcut_memo.clear
            super
          end
        end)
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

      # Registry of defined shortcut families: prefix => model class. Populated
      # by def_model_shortcuts, read by `shortcuts`. Lives on `main`.
      def shortcut_registry
        @shortcut_registry ||= {}
      end

      def register_shortcut(prefix, klass)
        shortcut_registry[prefix] = klass
      end

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
