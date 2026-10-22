require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

# Runs `partitia:support:install` in a child process: loading Rails' generators
# here would define `Rails` and break the suite's Rails-free charter.
RSpec.describe "partitia:support:install" do
  let(:line) { "migrations_paths: <%= Partitia::Support.migrations_paths[:primary] %>" }
  let(:root) { Dir.mktmpdir("partitia-support-install") }
  let(:db_yml) { File.join(root, "config/database.yml") }
  let(:fixtures) { File.expand_path("../fixtures/database_yml", __dir__) }

  after { FileUtils.rm_rf(root) }

  def install_fixture(name, at: db_yml)
    FileUtils.mkdir_p(File.dirname(at))
    FileUtils.cp(File.join(fixtures, name), at)
  end

  def run_generator
    lib = File.expand_path("../../lib", __dir__)
    script = <<~RUBY
      require "rails/generators"
      require "generators/partitia/support/install/install_generator"
      Partitia::Support::Generators::InstallGenerator.start([], destination_root: ARGV.fetch(0))
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script, root, stdin_data: "")
    expect(status).to be_success, out
    out
  end

  context "with a fresh `rails new` sqlite database.yml" do
    before { install_fixture("sqlite.yml") }

    it "wires development, test and production primary, leaving everything else as it was" do
      original = File.read(db_yml)
      out = run_generator
      wired = File.read(db_yml)

      expect(wired.scan(line).size).to eq(3)
      expect(wired).to include(
        "  database: storage/development.sqlite3\n  #{line}\n",
        "  database: storage/test.sqlite3\n  #{line}\n",
        "    database: storage/production.sqlite3\n    #{line}\n"
      )
      expect(wired.lines - [ "  #{line}\n", "    #{line}\n" ]).to eq(original.lines)
      expect(out).to include("nothing left to do")
    end

    it "changes nothing and asks nothing on a second run" do
      run_generator
      once = File.read(db_yml)
      out = run_generator

      expect(File.read(db_yml)).to eq(once)
      expect(out.scan("identical").size).to eq(3)
      expect(out).not_to match(/insert|Overwrite/)
    end
  end

  it "wires only the environments still missing" do
    install_fixture("postgresql.yml")
    File.write(db_yml, File.read(db_yml).sub("  database: app_test\n", "\\0  #{line}\n"))

    out = run_generator

    expect(File.read(db_yml).scan(line).size).to eq(3)
    expect(out).to include("identical  migrations_paths (test)")
  end

  it "says what to add, and where, when it cannot place the line" do
    FileUtils.mkdir_p(File.dirname(db_yml))
    File.write(db_yml, "development:\n  database: d\nproduction:\n  main:\n    database: p\n")

    out = run_generator

    expect(File.read(db_yml)).to eq("development:\n  database: d\n  #{line}\nproduction:\n  main:\n    database: p\n")
    expect(out).to include("the host still has to:")
    expect(out).to include("(test): no `test:` block found", "(production):")
    expect(out).to include("Add `#{line}`")
  end

  it "falls back to spec/dummy inside an engine" do
    install_fixture("sqlite.yml", at: File.join(root, "spec/dummy/config/database.yml"))

    run_generator

    expect(File.read(File.join(root, "spec/dummy/config/database.yml")).scan(line).size).to eq(3)
  end

  it "says so when there is no database.yml" do
    out = run_generator

    expect(out).to include("config/database.yml not found", "Create config/database.yml")
  end
end
