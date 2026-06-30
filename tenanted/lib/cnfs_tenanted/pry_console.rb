module CnfsTenanted
  # Tenant-aware Pry console enhancements. These are CONTRIBUTED to cnfs_dev's
  # console when cnfs_dev is present — cnfs_dev itself knows nothing about
  # tenancy. Activated from the Engine's `console` block (development/test).
  #
  # Adds:
  #   vst "apple"   -> switch the console into a tenant's database context
  #   t, ta, tc, tf, tl   -> Tenant shortcuts (via cnfs_dev's def_model_shortcuts)
  #   a, aa, ac, af, al   -> Account shortcuts
  #
  module PryConsole
    module_function

    def install!
      return unless defined?(CnfsDev) && defined?(Pry)

      Pry.config.hooks.add_hook(:when_started, :cnfs_tenanted_helpers) do |_target, _options, _pry_instance|
        main = TOPLEVEL_BINDING.receiver

        # cnfs_dev mixes its ConsoleMethods (which defines def_model_shortcuts)
        # into main via its own :when_started hook. Hook execution order between
        # the two gems isn't guaranteed, so ensure the mixin is present before
        # we rely on it.
        unless main.respond_to?(:def_model_shortcuts)
          main.extend(CnfsDev::PryExt::ConsoleMethods)
        end

        # Switch the console into a tenant's database context (blank clears it).
        main.define_singleton_method(:vst) do |tenant = ""|
          ApplicationRecord.current_tenant = tenant
        end

        main.def_model_shortcuts("t", Tenant)  if defined?(Tenant)
        main.def_model_shortcuts("a", Account) if defined?(Account)
      end
    end
  end
end
