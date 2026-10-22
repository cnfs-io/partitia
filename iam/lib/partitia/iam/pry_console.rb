module Partitia
  module Iam
    # OKF console enhancements contributed to partitia-dev's console. partitia-dev exposes
    # Activated from the Engine's `console` block (development/test).
    module PryConsole
      module_function

      def install!
        return unless defined?(Partitia::Dev)

        Partitia::Dev.console do |c|
          c.namespace(module_parent, "i")
        end
      end
    end
  end
end
