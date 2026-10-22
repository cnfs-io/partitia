require "rails/generators/base"

module Partitia
  module Cognito
    module Generators
      # Wires a host Rails app for the partitia-cognito auth broker:
      #
      #   bin/rails generate partitia:cognito:install
      #
      #   - mounts Partitia::Cognito::Engine at /auth in config/routes.rb
      #   - config/initializers/partitia_cognito.rb  (app-owned; registers the
      #     provider, wires the identity_resolver seam, sets the policy)
      #   - config/partitia_cognito.yml  (non-secret connection values per
      #     environment; development points at pcm's Authentik)
      #   - adds the OAuth :code, :state and :nonce params to filter_parameter_logging
      #
      # Idempotent (ARCHITECTURE §5): every write is guarded, so a second run
      # changes nothing and asks nothing. It never overwrites a host file.
      #
      # Unlike iam, the broker CANNOT boot unconfigured: identity_resolver and
      # provider have no defaults and raise ConfigurationError if used unset
      # (ADR 0004). The initializer satisfies both seams.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        # What a callback request carries that must never reach the log (§5).
        FILTERED_PARAMS = %w[code state nonce].freeze

        # pcm's stack/authentik (`pcm up authentik`, `pcm show authentik`).
        AUTHENTIK_URL = "http://localhost:9000".freeze

        class_option :mount_path,
                     type: :string,
                     default: "/auth",
                     desc: "Path to mount the broker engine (login/callback/logout live under it)"

        class_option :app_slug,
                     type: :string,
                     desc: "Authentik application slug (default: the app name, dasherized)"

        desc "Mount the broker engine, install the app-owned partitia-cognito " \
             "initializer and config/partitia_cognito.yml, and filter the OAuth " \
             "code/state/nonce params from the log."

        # 1. Mount the broker engine so <mount>/login, /callback, /logout resolve.
        def mount_engine
          if host_file("config/routes.rb").include?("Partitia::Cognito::Engine")
            say_status :skip, "config/routes.rb already mounts Partitia::Cognito::Engine", :yellow
          else
            route %(mount Partitia::Cognito::Engine => "#{mount_path}")
          end
        end

        # 2. App-owned initializer: registers the Authentik (OIDC) provider, wires
        #    the broker->IAM identity_resolver seam, and sets the sign-in policy.
        def create_initializer
          path = "config/initializers/partitia_cognito.rb"
          return say_status(:skip, "#{path} exists", :yellow) if host_file?(path)

          template "partitia_cognito.rb", path
        end

        # 3. Non-secret connection values. client_secret never goes here.
        def create_config
          path = "config/partitia_cognito.yml"
          return say_status(:skip, "#{path} exists", :yellow) if host_file?(path)

          template "partitia_cognito.yml", path
        end

        # 4. Keep the OAuth code, state and nonce out of the log (an earlier app logged
        #    code and state in clear; the nonce shows in the login redirect). Injects into the host's filter list; never rewrites it.
        def filter_oauth_params
          path = "config/initializers/filter_parameter_logging.rb"
          unless host_file?(path)
            create_file path, <<~RUBY
              # Partial matches are filtered too (e.g. :code also filters code_verifier).
              Rails.application.config.filter_parameters += #{filter_list}
            RUBY
            return
          end

          missing = missing_filters(host_file(path))
          return say_status(:skip, "#{path} already filters #{FILTERED_PARAMS.join(', ')}", :yellow) if missing.empty?

          anchor = /filter_parameters \+= \[\n?/
          if host_file(path).match?(anchor)
            inject_into_file path, "  #{missing.map { |p| ":#{p}" }.join(', ')},\n", after: anchor
          else
            append_to_file path, "\n# partitia-cognito: the OAuth code, state and nonce.\n" \
                                 "Rails.application.config.filter_parameters += #{filter_list(missing)}\n"
          end
        end

        def print_post_install
          say ""
          say "partitia-cognito installed.", :green
          say "  routes:      Partitia::Cognito::Engine mounted at #{mount_path}"
          say "  initializer: config/initializers/partitia_cognito.rb (app-owned; edit freely)"
          say "  config:      config/partitia_cognito.yml (issuer, client_id, scopes; no secrets)"
          say "  logging:     :code, :state and :nonce filtered (config/initializers/filter_parameter_logging.rb)"
          say ""
          say "Entry points:", :green
          say "  GET    #{mount_path}/login     start sign-in"
          say "  GET    #{mount_path}/callback  OIDC redirect URI (register this in Authentik)"
          say "  DELETE #{mount_path}/logout    sign out"
          say ""
          say "Still to do:", :yellow
          say "  1. pcm up authentik    (Authentik at #{AUTHENTIK_URL})"
          say "  2. In Authentik, an OAuth2/OpenID provider + application with slug '#{app_slug}',"
          say "     client ID '#{app_slug}', redirect URI http://localhost:3000#{mount_path}/callback"
          say "     (or edit issuer/client_id in config/partitia_cognito.yml to match yours)"
          say "  3. The client secret, never in a file under version control:"
          say "       bin/rails credentials:edit   ->  partitia_cognito: { client_secret: <value> }"
          say "     or PARTITIA_COGNITO_CLIENT_SECRET"
          say "  4. Production: PARTITIA_COGNITO_ISSUER and PARTITIA_COGNITO_CLIENT_ID (or credentials)"
          say "  5. identity_resolver in the initializer points at partitia-iam; change it if you don't use iam"
          say ""
        end

        private

        def mount_path
          options[:mount_path]
        end

        # Authentik slugs are [-a-z0-9_]; the issuer is per application slug.
        def app_slug
          @app_slug ||= (options[:app_slug].presence || default_app_slug)
        end

        def default_app_slug
          name = Rails.application&.class&.module_parent_name || File.basename(destination_root)
          name.to_s.underscore.dasherize.gsub(/[^a-z0-9_-]/, "-")
        end

        def issuer
          "#{AUTHENTIK_URL}/application/o/#{app_slug}/"
        end

        def host_file?(path)
          File.exist?(File.join(destination_root, path))
        end

        def host_file(path)
          File.read(File.join(destination_root, path))
        end

        def missing_filters(content)
          FILTERED_PARAMS.reject { |p| content.match?(/:#{p}\b|["']#{p}["']|%i\[[^\]]*\b#{p}\b/) }
        end

        def filter_list(params = FILTERED_PARAMS)
          "%i[#{params.join(' ')}]"
        end
      end
    end
  end
end
