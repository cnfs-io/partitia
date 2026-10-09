require "rails/generators/base"

module CnfsCognito
  module Generators
    # Wires a host Rails app for the cnfs_cognito auth broker:
    #
    #   bin/rails generate cnfs_cognito:install
    #
    #   - mounts CnfsCognito::Engine at /auth in config/routes.rb
    #   - config/initializers/cnfs_cognito.rb  (app-owned; registers the
    #     provider, wires the identity_resolver seam, sets the policy)
    #
    # Unlike iam, the broker CANNOT boot unconfigured: identity_resolver and
    # provider have no defaults and raise ConfigurationError if used unset
    # (ADR 0004). This generator lands the initializer that satisfies both seams
    # and the route mount the engine needs.
    #
    # The initializer is shipped as a template (single source of truth); each app
    # gets its own editable copy. Nothing here is loaded from the packaged gem at
    # runtime — it is all generator source.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :mount_path,
                   type: :string,
                   default: "/auth",
                   desc: "Path to mount the broker engine (login/callback/logout live under it)"

      desc "Mount the broker engine and install the app-owned cnfs_cognito " \
           "initializer (provider registration, identity_resolver seam, policy)."

      # 1. Mount the broker engine so /auth/login, /auth/callback, /auth/logout
      #    resolve. The callback path (<mount>/callback) is the redirect URI you
      #    register in Authentik.
      def mount_engine
        path = "config/routes.rb"
        if File.read(path).include?("CnfsCognito::Engine")
          say_status :skip, "routes.rb already mounts CnfsCognito::Engine", :yellow
        else
          route %(mount CnfsCognito::Engine => "#{options[:mount_path]}")
        end
      end

      # 2. App-owned initializer: registers the Authentik (OIDC) provider, wires
      #    the broker->IAM identity_resolver seam, and sets the sign-in policy.
      def create_initializer
        template "cnfs_cognito.rb", "config/initializers/cnfs_cognito.rb"
      end

      def print_post_install
        mount = options[:mount_path]
        say ""
        say "cnfs_cognito installed.", :green
        say "  - CnfsCognito::Engine mounted at #{mount} in config/routes.rb"
        say "  - config/initializers/cnfs_cognito.rb  (app-owned; edit freely)"
        say ""
        say "Before booting, provide the provider connection config (read via CnfsCognito::Config):", :yellow
        say "  issuer / client_id  — non-secret: config/cnfs_cognito.yml"
        say "                        (or CNFS_COGNITO_ISSUER / CNFS_COGNITO_CLIENT_ID)"
        say "  client_secret       — SECRET: bin/rails credentials:edit"
        say "                          cnfs_cognito:"
        say "                            client_secret: <value>"
        say "                        (or CNFS_COGNITO_CLIENT_SECRET) — never inline it"
        say ""
        say "In Authentik, set the provider's redirect URI to:", :yellow
        say "  http://<your-app-host>#{mount}/callback"
        say ""
        say "Then visit #{mount}/login to start the OIDC flow."
        say ""
      end
    end
  end
end
