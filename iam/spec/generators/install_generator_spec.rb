require "rails_helper"
require "rails/generators"
require "generators/partitia/iam/install/install_generator"

RSpec.describe Partitia::Iam::Generators::InstallGenerator do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:initializer) { root.join("config/initializers/partitia_iam.rb") }

  after { FileUtils.rm_rf(root) }

  def run_generator
    out = StringIO.new
    original = $stdout
    $stdout = out
    described_class.start([], destination_root: root.to_s)
    out.string
  ensure
    $stdout = original
  end

  def database_yml(body)
    root.join("config").mkpath
    root.join("config/database.yml").write(body)
  end

  it "writes the initializer naming the partitia_iam credentials key" do
    run_generator

    expect(initializer.read).to include("#     partitia_iam:\n#       hmac_key:")
    expect(initializer.read).not_to match(/^#\s+iam:$/)
  end

  it "copies no migrations" do
    run_generator

    expect(root.join("db/migrate")).not_to exist
  end

  it "changes nothing and asks nothing on a second run" do
    run_generator
    initializer.write("# edited by the host\n")

    expect(Thor::LineEditor).not_to receive(:readline)
    output = run_generator

    expect(initializer.read).to eq("# edited by the host\n")
    expect(output).to match(/skip.*partitia_iam\.rb exists/)
  end

  it "tells the host to run partitia:support:install when database.yml lacks the registry" do
    database_yml("development:\n  database: storage/development.sqlite3\n")

    expect(run_generator).to include("partitia:support:install")
  end

  it "does not ask for partitia:support:install when database.yml reads the registry" do
    database_yml("development:\n  migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>\n")

    output = run_generator

    expect(output).not_to include("partitia:support:install")
    expect(output).to match(/ok.*Partitia::Support\.migrations_paths/)
  end

  it "prints what the host still has to do" do
    output = run_generator

    expect(output).to include("PARTITIA_IAM_HMAC_KEY", "credentials.partitia_iam.hmac_key",
                              "include Partitia::Iam::Authenticatable",
                              "before_action :require_authentication", "PARTITIA_URN_PARTITION")
  end
end
