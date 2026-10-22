module Partitia
  module Dev
    # The object yielded to `Partitia::Dev.console { |c| ... }`. A thin DSL that records
    # a gem's contributions into the Partitia::Dev registries (see partitia_dev.rb); it
    # knows nothing about Pry and pulls in none of the pry_ext tree, so it is safe
    # to instantiate at gem-load time. Each contribution is stored as inert data
    # (modules, symbols, blocks) and interpreted later by the console hook /
    # ShortcutPlanner / Prompt.
    #
    # Contribution kinds:
    #
    #   c.namespace(mod, letter)     register a gem's model namespace and its
    #                                one-letter prefix. At session start the
    #                                planner enumerates the ActiveRecord models
    #                                under `mod` and defines a shortcut family for
    #                                each (see ShortcutPlanner), so gems declare a
    #                                namespace once instead of listing every model.
    #
    #   c.model(klass, letter)       register a single model with a one-letter
    #                                prefix. For top-level models that live outside
    #                                any gem namespace (e.g. a top-level `Tenant`),
    #                                so c.namespace can't discover them. The code
    #                                is derived from the class name the same way,
    #                                e.g. c.model(Tenant, "t") => tt, tta, ttf, ...
    #
    #   c.command(name) { ... }      a one-off bare console helper (e.g. :vst)
    #                                that isn't a model shortcut
    #
    #   c.prompt_segment(color:) {}  a prompt segment; the block returns the text
    #                                to show (nil / "" renders nothing), colorized
    #                                with a named color (installed into Prompt at
    #                                session start)
    #
    #   c.before_reset { ... }       a block run before each reset_project!
    #
    #   c.reset_task("okf:sync")     a rake task appended to the reset_project!
    #                                chain (after db:reset/seed)
    #
    class Builder
      # Register a gem's model namespace and its one-letter shortcut prefix. Two
      # gems may share a letter; ShortcutPlanner lengthens colliding codes until
      # unique.
      def namespace(mod, letter)
        Partitia::Dev.namespaces << { module: mod, letter: letter.to_s }
        self
      end

      # Register a single model with a one-letter prefix. For top-level models
      # that no c.namespace can reach. The code is derived from the class name
      # like any other; shares the planner's collision set so it can't clash with
      # auto-discovered codes.
      def model(klass, letter)
        Partitia::Dev.models << { klass: klass, letter: letter.to_s }
        self
      end

      def command(name, &body)
        raise ArgumentError, "command #{name.inspect} requires a block" unless body

        Partitia::Dev.commands << { name: name.to_sym, body: body }
        self
      end

      # color: a named color interpreted by Partitia::Dev::PryExt::Prompt at session
      # start. The block returns the segment's text (nil or "" => render nothing).
      # Stored as data here so this DSL stays free of the Prompt/Pry tree.
      def prompt_segment(color: nil, &body)
        raise ArgumentError, "prompt_segment requires a block" unless body

        Partitia::Dev.prompt_segments << { color: color, body: body }
        self
      end

      # Run a block before each in-console reset_project!.
      def before_reset(&body)
        raise ArgumentError, "before_reset requires a block" unless body

        Partitia::Dev.before_resets << body
        self
      end

      # Append a rake task name to the reset_project! chain (after db:reset/seed).
      def reset_task(task_name)
        Partitia::Dev.reset_tasks << task_name.to_s
        self
      end
    end
  end
end
