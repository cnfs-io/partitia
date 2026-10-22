require "rails_helper"
require "rails/generators"
require "generators/partitia/tenanted/views/views_generator"
require "tmpdir"

RSpec.describe Partitia::Tenanted::Generators::ViewsGenerator do
  let(:app) { Pathname.new(Dir.mktmpdir("tenanted-views")) }
  let(:engine_views) { Partitia::Tenanted::Engine.root.join("app/views") }

  after { FileUtils.remove_entry(app) }

  def run_generator(*args)
    generator = described_class.new(args, {}, destination_root: app.to_s)
    original = $stdout
    $stdout = StringIO.new
    generator.invoke_all
  ensure
    $stdout = original
  end

  def ejected
    Dir.glob("app/views/**/*", base: app.to_s).select { |f| app.join(f).file? }.sort
  end

  it "has a source root in the engine's views" do
    expect(Pathname.new(described_class.source_root)).to eq(engine_views)
  end

  it "ejects the tenant views verbatim" do
    run_generator("tenants")

    expect(ejected).to include("app/views/tenants/index.html.erb", "app/views/tenants/_form.html.erb")
    expect(ejected).to all(start_with("app/views/tenants/"))
    expect(app.join("app/views/tenants/index.html.erb").read)
      .to eq(engine_views.join("tenants/index.html.erb").read)
  end

  it "ejects the tenant_not_found view (the one its controller template names)" do
    run_generator("tenant_not_found")

    expect(ejected).to eq([ "app/views/tenant_not_found/unknown.html.erb" ])
  end

  it "ejects every resource when none is given" do
    run_generator

    expect(ejected.map { |f| f.split("/")[2] }.uniq).to contain_exactly("tenants", "tenant_not_found")
  end

  it "rejects a resource the gem doesn't have" do
    expect { run_generator("accounts") }.to raise_error(Thor::Error, /Unknown resource "accounts"/)
    expect(ejected).to be_empty
  end
end
