require "rails/generators/base"

module Partitia
  module Iam
    module Generators
      # Wires a host Rails app for the iam identity authority:
      #
      #   bin/rails generate partitia:iam:install
      #
      #   - config/initializers/partitia_iam.rb   (app-owned, documents the HMAC key
      #     and the host-tunable knobs; written once, never overwritten)
      #   - checks config/database.yml reads Partitia::Support.migrations_paths, the
      #     registry iam's migrations reach the app through (ARCHITECTURE §5, Q3).
      #     iam never copies migrations, and leaves database.yml to
      #     partitia:support:install, which owns it.
      #
      # Idempotent: a second run changes nothing and asks nothing.
      #
      # iam works with NO initializer in dev/test — the HMAC key falls back to a
      # non-secret development key and the single-tenant account handle is minted
      # and memoised on first use (ADR 0002 §2).
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        INITIALIZER = "config/initializers/partitia_iam.rb".freeze
        DATABASE_YML = "config/database.yml".freeze
        REGISTRY = "Partitia::Support.migrations_paths".freeze

        desc "Install the app-owned partitia-iam initializer and check database.yml " \
             "reads iam's migrations from the partitia-support registry."

        def create_initializer
          if File.exist?(File.join(destination_root, INITIALIZER))
            say_status :skip, "#{INITIALIZER} exists", :blue
          else
            template "partitia_iam.rb", INITIALIZER
          end
        end

        def check_migrations_paths
          @registry_wired = File.exist?(database_yml) && File.read(database_yml).include?(REGISTRY)
          if @registry_wired
            say_status :ok, "#{DATABASE_YML} reads #{REGISTRY}", :blue
          else
            say_status :missing, "#{DATABASE_YML} does not read #{REGISTRY}", :yellow
          end
        end

        def print_post_install
          say ""
          say "partitia-iam installed. Still to do:", :green
          unless @registry_wired
            say "  - bin/rails generate partitia:support:install  (points database.yml at the"
            say "    engines' migrations), then bin/rails db:migrate"
          end
          say "  - Production: set PARTITIA_IAM_HMAC_KEY or credentials.partitia_iam.hmac_key."
          say "    The development fallback is NOT a secret; production must not use it."
          say "  - First sign-in: bin/rails partitia:iam:bootstrap (TENANT=<subdomain> when multi-tenant)"
          say "    prints root's one-time LINK_TOKEN: sign in once at /auth/login?link_token=<it>."
          say "  - In each protected controller:"
          say "      include Partitia::Iam::Authenticatable"
          say "      before_action :require_authentication"
          say "  - Set the app's URN partition: PARTITIA_URN_PARTITION or"
          say "    config/partitia_urn.yml (ADR 0007; default \"#{Partitia::Support::UrnConfig::DEFAULT_PARTITION}\")."
          say ""
        end

        private

        def database_yml = File.join(destination_root, DATABASE_YML)
      end
    end
  end
end
