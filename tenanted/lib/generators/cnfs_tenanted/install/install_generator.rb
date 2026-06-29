require "rails/generators/base"

module CnfsTenanted
  module Generators
    # Wires a host Rails app for cnfs_tenanted multi-tenancy.
    #
    # This generator performs the host-app edits that an engine cannot do on its
    # own — most importantly the database.yml rewrite and the pre-boot require of
    # the migration-path registry, which must exist before Rails reads
    # database.yml (Rails 7.1+ evaluates database.yml ERB before initializers).
    #
    # The gem PROVIDES the models, controllers, views, concern, and tenant
    # migrations. This generator only WIRES the app to use them.
    #
    #   bin/rails generate cnfs_tenanted:install
    #
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Wire this app for cnfs_tenanted multi-tenancy (database.yml, " \
           "ApplicationRecord/Controller, host controllers, storage dir)."

      # 1. Pre-boot require of the registry, placed BEFORE Bundler.require so it
      #    exists when database.yml's ERB (and any engine registration) runs.
      def require_registry_pre_boot
        marker = 'require_relative "boot"'
        injection = <<~RUBY

          # Load the CNFS tenant migration-path registry before gems load, so
          # engines can register their tenant migration paths at gem-load time
          # and database.yml's ERB can read them. Must precede Bundler.require
          # and database.yml evaluation.
          require "cnfs_support/tenant_migrations"
        RUBY

        if File.read(application_rb).include?("cnfs_support/tenant_migrations")
          say_status :skip, "registry require already present in application.rb", :yellow
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
