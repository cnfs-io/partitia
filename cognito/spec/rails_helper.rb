ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require_relative "dummy/config/environment"

require "rspec/rails"
# Enforces "no network": WebMock disables real connections; the OIDC harness
# stubs the IdP HTTP surface (spec/support/oidc_helpers.rb).
require "webmock/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # The one live-container spec is opt-in only; the default suite passes with
  # Docker stopped (Plan 003 WS5). Run it with `--tag authentik`.
  config.filter_run_excluding :authentik

  # The broker's configuration + provider registry are process-level singletons;
  # reset them between examples so nothing leaks (order is randomized).
  config.before do
    CnfsCognito.reset_configuration!
    CnfsCognito::Providers::Registry.clear!
  end
end
