require "rails/generators/base"

module Iam
  module Generators
    # Wires a host Rails app for the iam identity authority:
    #
    #   bin/rails generate iam:install
    #
    #   - config/initializers/iam.rb   (app-owned Iam.configure block)
    #
    # iam works with NO initializer in dev/test — the HMAC key falls back to a
    # non-secret development key and the single-tenant account handle is minted
    # and memoised on first use (ADR 0002 §2). This generator exists to make the
    # production-critical seam (the HMAC key) and the two host-tunable knobs
    # (URN partition, pinned account handle) VISIBLE and editable in the app,
    # rather than buried in the gem's defaults.
    #
    # The initializer is shipped as a template (single source of truth); each app
    # gets its own editable copy. Nothing here is loaded from the packaged gem at
    # runtime — it is all generator source.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install the app-owned Iam.configure initializer (HMAC key, URN " \
           "partition, single-tenant account handle)."

      def create_initializer
        template "iam.rb", "config/initializers/iam.rb"
      end

      def print_post_install
        say ""
        say "iam installed.", :green
        say "  - config/initializers/iam.rb  (app-owned Iam.configure; edit freely)"
        say ""
        say "IMPORTANT for production:", :yellow
        say "  Set a real HMAC key via the IAM_HMAC_KEY env var or Rails"
        say "  credentials. The development fallback is NOT a secret — rotating"
        say "  to it in production would let anyone forge machine-credential"
        say "  secret digests."
        say ""
      end
    end
  end
end
