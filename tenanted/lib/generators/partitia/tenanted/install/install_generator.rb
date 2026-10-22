require "rails/generators/base"

module Partitia
  module Tenanted
    module Generators
      # Wires a host Rails app for partitia-tenanted multi-tenancy.
      #
      # This generator performs the host-app edits that an engine cannot do on its
      # own — the database.yml rewrite, the ApplicationRecord/Controller wiring,
      # and the thin host controllers.
      #
      # The gem PROVIDES the models, controllers, views, and concern. This
      # generator WIRES the app to use them.
      #
      # MIGRATIONS — this generator copies nothing
      #   The rewritten database.yml defaults each database to a conventional,
      #   hardcoded migrations_paths (db/migrate, db/global_migrate) — the app
      #   owns its migrations, pulled the standard Rails way:
      #
      #     bin/rails partitia_tenanted:install:migrations
      #     bin/rails railties:install:migrations
      #
      #   The template also carries a commented-out in-place alternative per
      #   database (reading straight from the gems via Partitia::Support.migrations_paths);
      #   uncommenting that line is the whole switch. See the template's header.
      #
      #   bin/rails generate partitia:tenanted:install
      #
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Wire this app for partitia-tenanted multi-tenancy (database.yml, " \
             "ApplicationRecord/Controller, host controllers, migrations, storage dir)."

        # 1. Make ApplicationRecord the tenanted connection class. The argument is
        #    the database.yml config name of the tenanted database ("tenant"); the
        #    adapter defaults to "primary", which this stack renamed.
        def tenant_application_record
          path = "app/models/application_record.rb"
          if File.read(path).match?(/^\s*tenanted\b/)
            say_status :skip, "ApplicationRecord already calls tenanted", :yellow
          else
            inject_into_file path, %(  tenanted "tenant"\n), after: /primary_abstract_class\n/
          end
        end

        # 1b. Show the migration-scope-name knobs in config/application.rb. The
        #     engine ships these defaults; a host renaming its databases edits the
        #     values here (and keeps them in sync with the `tenanted "<name>"`
        #     call above and the database.yml entry names). Injected as an explicit
        #     override so the seam is visible, not buried in the gem.
        def configure_migration_scopes
          path = "config/application.rb"
          if File.read(path).include?("Partitia::Support.migrations_paths_for")
            say_status :skip, "application.rb already sets migration scopes", :yellow
          else
            inject_into_file path, <<~RUBY.indent(4), after: /class Application < Rails::Application\n/

              # Migration scope names for partitia-tenanted. The engine ships these
              # defaults (tenant -> db/migrate, global -> db/global_migrate).
              # Rename the databases by editing the values here — keep these keys
              # in sync with your database.yml entry names and the
              # `tenanted "<name>"` call in app/models/application_record.rb.
              Partitia::Support.migrations_paths_for.replace(
                tenant: "db/migrate",
                global: "db/global_migrate"
              )
            RUBY
          end
        end

        # 2. Resolve the tenant from the subdomain in every request.
        def include_tenant_resolution
          path = "app/controllers/application_controller.rb"
          if File.read(path).include?("Partitia::Tenanted::TenantResolution")
            say_status :skip, "ApplicationController already includes TenantResolution", :yellow
          else
            inject_into_file path,
                             "  include Partitia::Tenanted::TenantResolution\n",
                             after: /class ApplicationController < ActionController::Base\n/
          end
        end

        # 3. Rewrite database.yml: tenanted `tenant` (one DB per tenant) + a plain
        #    `global` DB for the registry. Defaults to conventional hardcoded
        #    migrations_paths; the template carries a commented-out in-place
        #    alternative per database.
        def configure_database
          say_status :info, "Rewriting config/database.yml for multi-tenancy", :green
          template "database.yml", "config/database.yml", force: true
        end

        # 4. Development: make *.localhost subdomains resolve (tld_length 0).
        def configure_development_subdomains
          path = "config/environments/development.rb"
          if File.read(path).include?("tld_length")
            say_status :skip, "development.rb already sets tld_length", :yellow
          else
            inject_into_file path,
                             "\n  # Treat the first label of *.localhost as the tenant subdomain.\n" \
                             "  config.action_dispatch.tld_length = 0\n",
                             after: /Rails\.application\.configure do\n/
          end
        end

        # 5. Thin host controllers inheriting from the engine's, so routes resolve
        #    in the host namespace and the app can customize by overriding here.
        def create_host_controllers
          template "tenants_controller.rb", "app/controllers/tenants_controller.rb"
          template "tenant_not_found_controller.rb", "app/controllers/tenant_not_found_controller.rb"
        end

        # 5b. Initializer: tenant resolver + unknown-tenant handling.
        def create_initializer
          template "partitia_tenanted.rb", "config/initializers/partitia_tenanted.rb"
        end

        # 6. Per-tenant SQLite files live here.
        def create_tenant_storage_dir
          empty_directory "storage/tenants"
          create_file "storage/tenants/.keep" unless File.exist?("storage/tenants/.keep")
        end

        # 7. Create + migrate the GLOBAL database so the Tenant registry table
        #    exists. (Tenant databases are created/migrated on demand by
        #    activerecord-tenanted when each Tenant is created.)
        def migrate_global_database
          say_status :info, "Migrating the global database (tenant registry)", :green
          rails_command "db:migrate"
        end

        def show_post_install_message
          say <<~MSG, :green

            partitia-tenanted is installed. Next steps:

              1. Boot the server:           bin/rails server
              2. Bare domain  http://localhost:3000        -> tenant registry (tenants#index)
              3. Create a tenant in console:
                   Partitia::Tenanted::Tenant.create!(name: "Acme", subdomain: "acme", owner_email: "owner@acme.test")
              4. Visit         http://acme.localhost:3000   -> that tenant's app

            The tenant's database is provisioned automatically on creation, and
            the registered after_provision hooks seed its identity records.
          MSG
        end
      end
    end
  end
end
