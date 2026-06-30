require "rails/generators/base"

module CnfsTenanted
  module Generators
    # Wires a host Rails app for cnfs_tenanted multi-tenancy.
    #
    # This generator performs the host-app edits that an engine cannot do on its
    # own — the database.yml rewrite, the ApplicationRecord/Controller wiring,
    # the thin host controllers, and (by default) copying the gem's migrations
    # into the host.
    #
    # The gem PROVIDES the models, controllers, views, and concern. This
    # generator WIRES the app to use them and copies in migrations (copy-in is
    # the default; see the README for the in-place opt-in).
    #
    #   bin/rails generate cnfs_tenanted:install
    #
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Wire this app for cnfs_tenanted multi-tenancy (database.yml, " \
           "ApplicationRecord/Controller, host controllers, migrations, storage dir)."

      # 1. Write the in-place opt-in require into application.rb, COMMENTED OUT.
      #    Uncommenting this one line is the entire opt-in: each engine then
      #    appends its migration paths to the registry as it loads, and
      #    config/database.yml (which already checks `defined?`) feeds them to
      #    the right databases. No database.yml edit is ever needed.
      #
      #    It must sit ABOVE Bundler.require, because Rails evaluates
      #    database.yml before initializers — a config setting would be read
      #    too late.
      def write_inplace_optin
        marker = 'require_relative "boot"'
        injection = <<~RUBY

          # CNFS in-place migrations (opt-in): uncomment the line below to read
          # engine migrations directly from the gems instead of copying them
          # into this app. One source of truth across apps; a gem migration
          # change propagates on `bundle update`. Must stay above Bundler.require.
          # See the cnfs_tenanted README ("Migrations") for details.
          # require "cnfs_support/engine_migration_paths"
        RUBY

        if File.read(application_rb).include?("cnfs_support/engine_migration_paths")
          say_status :skip, "in-place opt-in already present in application.rb", :yellow
        else
          inject_into_file application_rb, injection, after: marker
        end
      end

      # 2. Make ApplicationRecord the tenanted connection class.
      def tenant_application_record
        path = "app/models/application_record.rb"
        if File.read(path).match?(/^\s*tenanted\b/)
          say_status :skip, "ApplicationRecord already calls tenanted", :yellow
        else
          inject_into_file path, "  tenanted\n", after: /primary_abstract_class\n/
        end
      end

      # 3. Resolve the tenant from the subdomain in every request.
      def include_tenant_resolution
        path = "app/controllers/application_controller.rb"
        if File.read(path).include?("CnfsTenanted::TenantResolution")
          say_status :skip, "ApplicationController already includes TenantResolution", :yellow
        else
          inject_into_file path,
                           "  include CnfsTenanted::TenantResolution\n",
                           after: /class ApplicationController < ActionController::Base\n/
        end
      end

      # 4. Rewrite database.yml: tenanted primary (one DB per tenant) + a plain
      #    global DB for the registry, with the tenanted migrations_paths read
      #    from the registry.
      def configure_database
        say_status :info, "Rewriting config/database.yml for multi-tenancy", :green

        template "database.yml", "config/database.yml", force: true
      end

      # 5. Development: make *.localhost subdomains resolve (tld_length 0).
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

      # 6. Thin host controllers inheriting from the engine's, so routes resolve
      #    in the host namespace and the app can customize by overriding here.
      def create_host_controllers
        template "tenants_controller.rb", "app/controllers/tenants_controller.rb"
        template "accounts_controller.rb", "app/controllers/accounts_controller.rb"
      end

      # 7. Per-tenant SQLite files live here.
      def create_tenant_storage_dir
        empty_directory "storage/tenants"
        create_file "storage/tenants/.keep" unless File.exist?("storage/tenants/.keep")
      end

      # 8. Create + migrate the GLOBAL database so the Tenant registry table
      #    exists. (Tenant databases are created/migrated on demand by
      #    activerecord-tenanted when each Tenant is created.)
      def migrate_global_database
        say_status :info, "Migrating the global database (tenant registry)", :green
        rails_command "db:migrate"
      end

      def show_post_install_message
        say <<~MSG, :green

          cnfs_tenanted is installed. Next steps:

            1. Boot the server:           bin/rails server
            2. Bare domain  http://localhost:3000        -> tenant registry (tenants#index)
            3. Create a tenant in console:
                 Tenant.create!(name: "Acme", subdomain: "acme")
            4. Visit         http://acme.localhost:3000   -> that tenant's account settings

          The tenant's database (storage/tenants/acme.sqlite3) and its Account
          settings singleton are provisioned automatically on creation.
        MSG
      end

      private

      def application_rb
        "config/application.rb"
      end
    end
  end
end
