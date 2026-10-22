module Partitia
  module Tenanted
    # Tenant-aware Pry console enhancements, contributed to partitia-dev's console.
    # partitia-dev itself knows nothing about tenancy; it just exposes the
    # Partitia::Dev.console facade, and this fills in the tenant specifics. Activated
    # from the Engine's `console` block (development/test).
    #
    # Contributes:
    #   vst "acme"          -> switch the console into a tenant's DB context
    #   vst                 -> clear back to the global/untenanted context
    #   tt, tta, ttf, ...   -> Tenant shortcuts
    #   prompt segment      -> blue [tenant] while a tenant context is active
    #
    # Tenant is a top-level model (no gem namespace), so it is registered
    # individually with c.model rather than discovered via c.namespace.
    module PryConsole
      module_function

      def install!
        return unless defined?(Partitia::Dev)

        Partitia::Dev.console do |c|
          c.command(:switch!) do |tenant = ""|
            ApplicationRecord.current_tenant = tenant
          end

          c.model(Partitia::Tenanted::Tenant, "t")

          c.prompt_segment(color: :blue) do
            ApplicationRecord.current_tenant rescue nil
          end
        end
      end
    end
  end
end
