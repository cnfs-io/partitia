ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require_relative "dummy/config/environment"

require "rspec/rails"
# Fresh checkouts (CI) have no test databases: create and load the global schema
ActiveRecord::Migration.maintain_test_schema!
# Plan 004 integration specs stub the IdP HTTP surface (reused OIDC harness).
# WebMock disables real net connections; Plan 001 specs make none.
require "webmock/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Multi-database tenanted setup: transactional fixtures would wrap the global
  # DB in a transaction invisible to the separate tenant-DB connections, so we
  # manage cleanup explicitly (see spec/support/tenancy.rb).
  config.use_transactional_fixtures = false

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
