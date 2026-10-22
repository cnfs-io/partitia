require_relative "boot"

require "rails"
# The broker is DB-less: it owns no tables and stores no identities, so no
# active_record railtie. It needs Action Controller/View (the SessionsController
# + flash) and the session/cookie middleware Rails provides by default.
require "action_controller/railtie"
require "action_view/railtie"

# Require the gems listed in the Gemfile (loads cnfs_cognito + its engine).
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    config.eager_load = false
    # Cookie-based session/flash signing for the OIDC state/nonce/PKCE stash.
    config.secret_key_base = "cnfs-cognito-dummy-secret-key-base-not-a-secret"

    config.autoload_lib(ignore: %w[assets tasks])

    config.generators.system_tests = nil
  end
end
