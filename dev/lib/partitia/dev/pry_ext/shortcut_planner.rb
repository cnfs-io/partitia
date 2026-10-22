module Partitia
  module Dev
    module PryExt
      # Turns the namespace registry (populated via Partitia::Dev.console { |c|
      # c.namespace Partitia::Okf, "o" }) into a concrete list of model shortcuts,
      # deriving each shortcut code from the model's class name and resolving
      # collisions deterministically. Pure logic: it knows nothing about Pry or
      # the console `main` object, so it can be unit-tested in isolation.
      #
      # For each registered [namespace module, prefix letter] the planner finds
      # the ActiveRecord models directly under that namespace and assigns each a
      # code of the form <prefix_letter><model_code>, e.g.:
      #
      #   c.namespace Partitia::Okf, "o"   # Partitia::Okf::Bundle       => "ob"
      #   c.namespace Chorus,  "c"   # Chorus::Account       => "ca"
      #                              # Chorus::Agent         => "cag"
      #                              # Chorus::AgentProfile  => "cap"
      #
      # Code derivation (the <model_code> half) from the CamelCase class name:
      #
      #   * >= 2 capitals => the initials ("AgentProfile" => "ap"). On collision,
      #     use a 3rd+ capital if one exists, otherwise extend into the LAST word
      #     from its capital ("ap" -> "apr" -> "apro" -> ... from "Profile").
      #   * 1 capital     => the first letter ("Agent" => "a"), extended one
      #     letter at a time on collision ("a" -> "ag" -> "age" -> ...).
      #
      # Uniqueness is checked against the FULL concatenated shortcut across the
      # whole registry (not per namespace), so two gems may register the same
      # prefix letter (e.g. Chorus and Curry both "c"); collisions just lengthen
      # the code until unique. Models are processed in a stable order (namespace
      # registration order, then class name alphabetically) so the outcome is
      # deterministic across boots. If a code cannot be made unique even after
      # consuming the entire class name (vanishingly unlikely), that model is
      # skipped -- first come, first served.
      module ShortcutPlanner
        module_function

        # registry: array of { module:, letter: } (see Partitia::Dev.namespaces).
        # models:   array of { klass:, letter: }  (see Partitia::Dev.models) for
        #           top-level models that no namespace can reach.
        # Returns an array of { prefix:, klass: } ready for def_model_shortcuts.
        # Namespaces are planned first, then explicit models, all sharing one
        # collision set so the two kinds never clash.
        def plan(registry, models: [], claimed: [])
          claimed = claimed.dup
          plans   = []

          registry.each do |entry|
            models_for(entry[:module]).sort_by(&:name).each do |klass|
              plan_one(klass, entry[:letter].to_s, claimed, plans)
            end
          end

          models.each do |entry|
            plan_one(entry[:klass], entry[:letter].to_s, claimed, plans)
          end

          plans
        end

        # Assign a code to one model against the shared claimed set and append the
        # resulting { prefix:, klass: } to plans (skipping if no code is free).
        def plan_one(klass, letter, claimed, plans)
          code = assign_code(letter, klass.name.split("::").last, claimed)
          return unless code

          claimed << code
          plans << { prefix: code, klass: klass }
        end

        # ActiveRecord models defined DIRECTLY under `mod` (not nested deeper),
        # excluding abstract classes. Relies on models already being loaded (the
        # console hook eager-loads before planning).
        def models_for(mod)
          return [] unless defined?(ActiveRecord::Base)

          prefix = "#{mod.name}::"
          ActiveRecord::Base.descendants.select do |klass|
            name = klass.name
            next false if name.nil?
            next false unless name.start_with?(prefix)
            next false if name[prefix.length..].include?("::") # skip deeper nesting
            next false if klass.abstract_class?

            true
          end
        end

        # Walk the candidate codes for `class_name` (prepended with `letter`) and
        # return the first whose full shortcut isn't already in `claimed`, or nil
        # if every candidate collides.
        def assign_code(letter, class_name, claimed)
          candidates(class_name).each do |code|
            full = "#{letter}#{code}"
            return full unless claimed.include?(full)
          end
          nil
        end

        # Ordered list of candidate model codes (without the namespace letter),
        # most-preferred first. See the module comment for the rules.
        def candidates(class_name)
          words    = class_name.scan(/[A-Z][a-z0-9]*/)
          capitals = words.map { |w| w[0].downcase }

          if capitals.length >= 2
            # initials (2 letters), then 3rd+ capitals if present, then extend
            # the last word letter by letter from its capital.
            seeds = (2..capitals.length).map { |n| capitals.first(n).join }
            seeds + extend_word(capitals.first(2).join, words.last[1..].to_s.downcase)
          else
            # single word: first letter, then extend letter by letter.
            extend_word("", class_name.downcase)
          end
        end

        # Given a fixed `base` and a `tail` string, produce base plus
        # progressively longer prefixes of tail:
        #   extend_word("ap", "rofile") => ["apr", "apro", "aprof", ...]
        #   extend_word("",   "agent")  => ["a", "ag", "age", "agen", "agent"]
        def extend_word(base, tail)
          (1..tail.length).map { |n| base + tail[0, n] }
        end
      end
    end
  end
end
