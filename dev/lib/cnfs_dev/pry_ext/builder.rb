module CnfsDev
  module PryExt
    # The object yielded to `CnfsDev.console { |c| ... }`. It records a gem's
    # console contributions into the shared registries; it knows nothing about
    # Pry. Applied to the console `main` object later, in a single hook at
    # session start (see CnfsDev::PryExt.setup!).
    #
    # Contribution kinds:
    #
    #   c.shortcuts(prefix, klass)   model shortcut family (delegates to
    #                                ConsoleMethods#def_model_shortcuts at apply
    #                                time, so the live `main` defines them)
    #
    #   c.command(name) { ... }      a one-off bare console helper (e.g. :vst)
    #                                that isn't a model shortcut
    #
    #   c.prompt_segment(color:) {}  a prompt segment; the block returns the
    #                                text to show (nil / "" renders nothing),
    #                                colorized with a named color
    #
    #   c.before_reset { ... }       a block run before each reset_project!
    #                                (delegates to ConsoleMethods#before_project_reset)
    #
    #   c.reset_task("okf:sync")     a rake task appended to the reset_project!
    #                                chain (delegates to project_reset_tasks)
    #
    class Builder
      # Pending contributions, drained when the console session starts.
      def self.shortcuts    = (@shortcuts    ||= [])
      def self.commands     = (@commands     ||= [])
      def self.before_resets = (@before_resets ||= [])
      def self.reset_tasks  = (@reset_tasks  ||= [])

      # Run a consuming gem's block against a fresh builder.
      def self.collect
        builder = new
        yield builder
        builder
      end

      def shortcuts(prefix, klass)
        Builder.shortcuts << { prefix: prefix, klass: klass }
        self
      end

      def command(name, &body)
        raise ArgumentError, "command #{name.inspect} requires a block" unless body

        Builder.commands << { name: name.to_sym, body: body }
        self
      end

      # color: a name from CnfsDev::PryExt::Prompt::COLORS (:blue, :green, ...).
      # The block returns the segment's text (nil or "" => render nothing).
      def prompt_segment(color: nil, &body)
        raise ArgumentError, "prompt_segment requires a block" unless body

        Prompt.register_segment(color: color, &body)
        self
      end

      # Run a block before each in-console reset_project!.
      def before_reset(&body)
        raise ArgumentError, "before_reset requires a block" unless body

        Builder.before_resets << body
        self
      end

      # Append a rake task name to the reset_project! chain (after db:reset/seed).
      def reset_task(task_name)
        Builder.reset_tasks << task_name.to_s
        self
      end
    end
  end
end
