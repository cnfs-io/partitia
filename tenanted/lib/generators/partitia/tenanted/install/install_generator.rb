require "erb"
require "yaml"
require "rails/generators/base"

module Partitia
  module Tenanted
    module Generators
      # Wires a host Rails app for partitia-tenanted multi-tenancy:
      #
      #   bin/rails generate partitia:tenanted:install
      #
      # The gem provides the models, controllers, views, routes (/tenants,
      # /tenant-unknown) and the migration scopes (the engine registers the
      # :tenant and :global planes with Partitia::Support). This generator does the
      # host-app edits the engine cannot: database.yml, ApplicationRecord and
      # ApplicationController, development subdomains, the thin host controllers
      # and the initializer.
      #
      # Idempotent: every write is guarded, so a second run changes nothing and
      # asks nothing. database.yml is written only when it is missing or is still
      # the stock single-database file `rails new` produces; a customized file
      # without the tenanted layout stops the generator, before anything is
      # changed, with the layout to adopt.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Wire this app for partitia-tenanted multi-tenancy (database.yml planes, " \
             "ApplicationRecord/Controller, host controllers, initializer)."

        DATABASE_YML = "config/database.yml".freeze
        ENVIRONMENTS = %w[development test production].freeze
        SOLID_DATABASES = %w[cache queue cable].freeze

        # A stop (customized database.yml) exits non-zero, so a script running
        # the generator (cnfs new, an app template) sees it.
        def self.exit_on_failure? = true

        # 1. database.yml first, so a customized file stops the run before any
        #    other file is touched.
        def configure_database
          case database_config_state
          when :tenanted
            say_status :skip, "#{DATABASE_YML} already has the global and tenant planes", :yellow
          when :missing, :stock
            template "database.yml", DATABASE_YML, force: true # §5: stock file only
          else
            say database_change_instructions, :red
            raise Thor::Error, "#{DATABASE_YML} is customized; not changed. Apply the layout above and re-run."
          end
        end

        # 2. Make ApplicationRecord the tenanted connection class. The argument is
        #    the database.yml config name of the tenanted database ("tenant").
        def tenant_application_record
          path = "app/models/application_record.rb"
          if read(path).match?(/^\s*tenanted\b/)
            say_status :skip, "ApplicationRecord already calls tenanted", :yellow
          else
            inject_into_file path, %(  tenanted "tenant"\n), after: /primary_abstract_class\n/
          end
        end

        # 3. Resolve the tenant from the request in every controller.
        def include_tenant_resolution
          path = "app/controllers/application_controller.rb"
          if read(path).include?("Partitia::Tenanted::TenantResolution")
            say_status :skip, "ApplicationController already includes TenantResolution", :yellow
          else
            inject_into_file path,
                             "  include Partitia::Tenanted::TenantResolution\n",
                             after: /class ApplicationController < ActionController::Base\n/
          end
        end

        # 4. Development: make *.localhost subdomains resolve (tld_length 0).
        def configure_development_subdomains
          path = "config/environments/development.rb"
          if read(path).include?("tld_length")
            say_status :skip, "development.rb already sets tld_length", :yellow
          else
            inject_into_file path,
                             "\n  # Treat the first label of *.localhost as the tenant subdomain.\n" \
                             "  config.action_dispatch.tld_length = 0\n",
                             after: /Rails\.application\.configure do\n/
          end
        end

        # 5. Thin host controllers inheriting from the engine's, so the routes the
        #    engine draws resolve in the host namespace and the app can override.
        def create_host_controllers
          guarded_template "tenants_controller.rb", "app/controllers/tenants_controller.rb"
          guarded_template "tenant_not_found_controller.rb", "app/controllers/tenant_not_found_controller.rb"
        end

        # 6. Initializer: resolver, unknown-tenant handling, console guard.
        def create_initializer
          guarded_template "partitia_tenanted.rb", "config/initializers/partitia_tenanted.rb"
        end

        # 7. Create and migrate the GLOBAL database so the Tenant registry exists.
        #    Tenant databases are created and migrated by activerecord-tenanted
        #    when each Tenant is created.
        def migrate_global_database
          rails_command "db:migrate"
        end

        def show_post_install_message
          say <<~MSG, :green

            partitia-tenanted is installed.

            Entry points (drawn into your routes by the engine):
              /tenants          tenant registry, the platform console (denied until step 1)
              /tenant-unknown   landing page for a subdomain with no tenant

            Still to do:
              1. Decide who may use the platform console: set
                 Partitia::Tenanted.platform_console_guard in
                 config/initializers/partitia_tenanted.rb. Unset, it answers 403.
              2. Provision the reserved platform database, once per environment:
                   bin/rails runner 'Partitia::Tenanted.provision_platform!(owner_email: "you@example.com")'
              3. Create a tenant, then visit http://<subdomain>.localhost:3000
                   Partitia::Tenanted::Tenant.create!(name: "Acme", subdomain: "acme", owner_email: "owner@acme.test")

            Migration status of the global, platform and tenant databases:
              bin/rails partitia:tenanted:migrate:status
          MSG
        end

        private

        def read(path)
          File.read(File.join(destination_root, path))
        end

        def guarded_template(source, path)
          if File.exist?(File.join(destination_root, path))
            say_status :skip, "#{path} already exists", :yellow
          else
            template source, path
          end
        end

        # The template's production section repeats the stock file's Solid
        # databases (cache, queue, cable), so an app keeps what `rails new` gave it.
        def solid_databases
          @solid_databases || []
        end

        # :missing, :tenanted (every environment has a global database and a
        # tenanted one), :stock (still what `rails new` wrote for SQLite) or
        # :custom (anything else: never rewritten).
        def database_config_state
          path = File.join(destination_root, DATABASE_YML)
          return :missing unless File.exist?(path)

          config = parse_database_yml(File.read(path))
          return :custom unless config.is_a?(Hash)
          return :tenanted if tenanted_layout?(config)
          return :stock if stock_layout?(config)

          :custom
        end

        # YAML with ERB tags replaced by a placeholder: the shape is all that
        # matters here, and evaluating the host's ERB is not this generator's job.
        def parse_database_yml(content)
          yaml = content.gsub(/<%=.*?%>/m, "ERB").gsub(/<%.*?%>/m, "")
          YAML.safe_load(yaml, aliases: true)
        rescue Psych::Exception
          nil
        end

        def tenanted_layout?(config)
          ENVIRONMENTS.all? { |env| tenanted_environment?(config[env]) }
        end

        def tenanted_environment?(dbs)
          dbs.is_a?(Hash) && dbs["global"].is_a?(Hash) &&
            dbs.values.any? { |db| db.is_a?(Hash) && db["tenanted"] == true }
        end

        # Conservative: the SQLite file `rails new` writes (Rails 8, with or
        # without Solid, with or without Kamal), compared by structure. Any extra
        # key or changed value makes it custom.
        def stock_layout?(config)
          return false unless config.keys.sort == (ENVIRONMENTS + [ "default" ]).sort

          base = config["default"]
          return false unless stock_default?(base)
          return false unless config["development"] == base.merge("database" => "storage/development.sqlite3")
          return false unless config["test"] == base.merge("database" => "storage/test.sqlite3")

          stock_production?(config["production"], base)
        end

        def stock_default?(base)
          pool_key = (base.keys & %w[max_connections pool]).first
          pool_key && base == { "adapter" => "sqlite3", pool_key => "ERB", "timeout" => 5000 }
        end

        def stock_production?(production, base)
          return false unless production.is_a?(Hash)
          return stock_database?(production, base, "storage/production.sqlite3") unless production.key?("primary")

          solid = production.keys - [ "primary" ]
          return false unless (solid - SOLID_DATABASES).empty?
          return false unless stock_database?(production["primary"], base, "storage/production.sqlite3")

          ok = solid.all? do |name|
            stock_database?(production[name], base, "storage/production_#{name}.sqlite3",
                            "migrations_paths" => "db/#{name}_migrate")
          end
          @solid_databases = solid if ok
          ok
        end

        # The --skip-kamal variant leaves `database:` commented out.
        def stock_database?(db, base, database, extra = {})
          expected = base.merge(extra)
          [ expected, expected.merge("database" => database) ].include?(db)
        end

        def database_change_instructions
          config = parse_database_yml(read(DATABASE_YML))
          config = {} unless config.is_a?(Hash)
          missing = ENVIRONMENTS.reject { |env| tenanted_environment?(config[env]) }

          <<~MSG

            #{DATABASE_YML} is not the stock file `rails new` writes, so partitia-tenanted
            will not rewrite it. These environments lack the global and tenant databases:
            #{missing.join(', ')}

            Give each environment a `global` database and a `tenant` database with
            `tenanted: true`, each taking its migrations from the registry (keep any
            other databases you have, e.g. production cache/queue/cable):

            #{rendered_database_template.gsub(/^/, '    ')}
          MSG
        end

        def rendered_database_template
          source = File.read(File.join(self.class.source_root, "database.yml"))
          ERB.new(source, trim_mode: "-").result(binding)
             .lines.reject { |l| l.start_with?("#") }.join.gsub(/\n{3,}/, "\n\n").strip
        end
      end
    end
  end
end
