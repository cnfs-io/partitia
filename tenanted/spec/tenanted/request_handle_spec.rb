require "rails_helper"

# D6: the Rack-layer resolver the engine gives activerecord-tenanted's middleware,
# so mounted engines (cognito's /auth callback) run in the tenant's database.
RSpec.describe "Partitia::Tenanted.request_handle" do
  it "maps a registered subdomain to its tenant's handle" do
    tenant = create_tenant!(subdomain: "acme")

    expect(Partitia::Tenanted.request_handle(FakeRequest.new(host: "acme.localhost"))).to eq(tenant.handle)
  end

  it "is nil for an unknown subdomain, no subdomain and the reserved handle" do
    create_tenant!(subdomain: "acme")

    expect(Partitia::Tenanted.request_handle(FakeRequest.new(host: "bogus.localhost"))).to be_nil
    expect(Partitia::Tenanted.request_handle(FakeRequest.new(host: "localhost"))).to be_nil
    expect(Partitia::Tenanted.request_handle(FakeRequest.new(host: "platform.localhost"))).to be_nil
  end

  it "follows the app's tenant_resolver" do
    tenant = create_tenant!(subdomain: "acme")
    Partitia::Tenanted.tenant_resolver = Partitia::Tenanted::Resolvers::Header.new

    request = FakeRequest.new(host: "localhost", headers: { "HTTP_X_TENANT_ID" => "acme" })
    expect(Partitia::Tenanted.request_handle(request)).to eq(tenant.handle)
  end

  it "is what the engine hands activerecord-tenanted's middleware" do
    initializer = Partitia::Tenanted::Engine.initializers.find { |i| i.name == "partitia_tenanted.rack_tenant_selection" }
    config = Struct.new(:active_record_tenanted).new(ActiveSupport::OrderedOptions.new)
    app = Struct.new(:config).new(config)
    initializer.run(app)
    tenant = create_tenant!(subdomain: "acme")

    expect(app.config.active_record_tenanted.tenant_resolver.call(FakeRequest.new(host: "acme.localhost"))).to eq(tenant.handle)
  end
end
