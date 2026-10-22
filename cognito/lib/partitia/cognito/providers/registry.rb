module CnfsCognito
  module Providers
    # Register/lookup providers by name. The point is only that nothing outside a
    # provider knows which IdP is configured — CnfsCognito.provider is typically
    # Registry.fetch(:authentik), configured by the host.
    module Registry
      module_function

      def register(name, provider)
        registry[name.to_sym] = provider
      end

      def fetch(name)
        registry.fetch(name.to_sym) do
          raise CnfsCognito::ConfigurationError, "no provider registered as #{name.inspect}"
        end
      end

      def registered?(name)
        registry.key?(name.to_sym)
      end

      def clear!
        registry.clear
      end

      def registry
        @registry ||= {}
      end
    end
  end
end
