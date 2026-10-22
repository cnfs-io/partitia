module CnfsDev
  # Only define the Railtie when Rails is present. This gem is a general
  # support library that may be required outside a Rails process (plain Ruby
  # scripts, non-Rails rake tasks, specs that don't boot Rails), where
  # ::Rails::Railtie would be an uninitialized constant.
  if defined?(Rails::Railtie)
    class Railtie < ::Rails::Railtie
      # Rails runs `console` blocks only when a Rails console session starts
      # (rails console / bin/rails c), so the Pry wiring never loads in the
      # web or job processes.
      console do
        require_relative "pry_ext"
        CnfsDev::PryExt.setup!
      end
    end
  end
end
