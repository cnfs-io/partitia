module Iam
  # OKF console enhancements contributed to cnfs_dev's console. cnfs_dev exposes
  # Activated from the Engine's `console` block (development/test).
  module PryConsole
    module_function

    def install!
      return unless defined?(CnfsDev)

      CnfsDev.console do |c|
        c.namespace(module_parent, "i")
      end
    end
  end
end
