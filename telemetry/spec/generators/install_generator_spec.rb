require "spec_helper"
require "tmpdir"
require "rails/generators"
require "generators/partitia/telemetry/install/install_generator"

RSpec.describe Partitia::Telemetry::Generators::InstallGenerator do
  let(:root) { Dir.mktmpdir }
  let(:commands) { [] }

  before do
    File.write(File.join(root, "Gemfile"), %(source "https://rubygems.org"\ngem "rails"\n))
    # `bundle add` is the one side effect outside the destination; record it and
    # mimic its Gemfile edit so the second run sees the gems.
    allow_any_instance_of(described_class).to receive(:bundle_add) do |_gen, names|
      commands << "bundle add #{names.join(" ")}"
      File.open(File.join(root, "Gemfile"), "a") { |f| names.each { |n| f.puts %(gem "#{n}") } }
    end
  end

  after { FileUtils.remove_entry(root) }

  def generate
    out = StringIO.new
    $stdout = out
    described_class.start([], destination_root: root)
    out.string
  ensure
    $stdout = STDOUT
  end

  def read(path) = File.read(File.join(root, path))

  it "adds the SDK, exporter and sentry-rails, and writes both initializers" do
    output = generate

    expect(commands).to eq([ "bundle add opentelemetry-sdk opentelemetry-exporter-otlp sentry-rails" ])
    expect(read("config/initializers/opentelemetry.rb")).to include("Partitia::Telemetry::Config", "sdk_traces_endpoint")
    expect(read("config/initializers/sentry.rb")).to include("error_reporting?", "Sentry.init")
    expect(output).to include("pt services", "PARTITIA_TELEMETRY_ERROR_DSN")
  end

  # sentry-rails leaves it off: without it Rails.error.report never reaches GlitchTip
  it "subscribes Sentry to the Rails error reporter" do
    generate

    expect(read("config/initializers/sentry.rb")).to include("config.rails.register_error_subscriber = true")
  end

  it "writes no endpoint or DSN literal into the app" do
    generate

    initializers = read("config/initializers/opentelemetry.rb") + read("config/initializers/sentry.rb")
    code = initializers.lines.grep_v(/^\s*#/).join
    expect(code).not_to match(%r{https?://})
    expect(code).not_to include("ENV")
  end

  it "adds only the gems that are missing" do
    File.write(File.join(root, "Gemfile"), %(gem "opentelemetry-sdk"\ngem 'sentry-rails', "~> 5"\n))
    generate
    expect(commands).to eq([ "bundle add opentelemetry-exporter-otlp" ])
  end

  it "changes nothing and asks nothing on a second run" do
    generate
    commands.clear
    File.write(File.join(root, "config/initializers/sentry.rb"), "# edited by the app\n")
    snapshot = Dir.glob("**/*", base: root).sort.to_h { |f| [ f, File.file?(File.join(root, f)) && read(f) ] }

    expect_any_instance_of(Thor::Shell::Basic).not_to receive(:ask)
    expect_any_instance_of(Thor::Shell::Basic).not_to receive(:yes?)
    output = generate

    expect(commands).to be_empty
    expect(Dir.glob("**/*", base: root).sort.to_h { |f| [ f, File.file?(File.join(root, f)) && read(f) ] }).to eq(snapshot)
    expect(output).to include("skip", "identical")
  end
end
