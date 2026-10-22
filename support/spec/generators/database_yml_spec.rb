require_relative "../../lib/generators/partitia/support/install/database_yml"

RSpec.describe Partitia::Support::Generators::DatabaseYml do
  let(:envs) { %w[development test production] }
  let(:line) { described_class::LINE }

  def fixture(name) = File.read(File.expand_path("../fixtures/database_yml/#{name}", __dir__))

  def points_for(content) = described_class.new(content).points(envs).to_h { |p| [ p.env, p ] }

  def anchor_line(content, point) = content.lines[point.line_index]

  context "with a fresh `rails new` sqlite database.yml" do
    let(:content) { fixture("sqlite.yml") }
    let(:points) { points_for(content) }

    it "anchors the flat development and test blocks on their database: line" do
      expect(anchor_line(content, points["development"])).to eq("  database: storage/development.sqlite3\n")
      expect(points["development"].indent).to eq("  ")
      expect(anchor_line(content, points["test"])).to eq("  database: storage/test.sqlite3\n")
    end

    it "anchors production on primary: only, at primary's indent" do
      expect(anchor_line(content, points["production"])).to eq("    database: storage/production.sqlite3\n")
      expect(points["production"].indent).to eq("    ")
    end
  end

  context "with a postgresql multi-database production (anchored primary:)" do
    let(:content) { fixture("postgresql.yml") }
    let(:points) { points_for(content) }

    it "does not depend on sqlite filenames" do
      expect(points.values.map(&:status)).to all(eq(:inject))
      expect(anchor_line(content, points["development"])).to eq("  database: app_development\n")
      expect(anchor_line(content, points["production"])).to eq("    database: app_production\n")
    end
  end

  it "reports an environment already wired as present" do
    content = fixture("sqlite.yml").sub("  database: storage/test.sqlite3\n", "\\0  #{line}\n")
    expect(points_for(content)["test"].status).to eq(:present)
  end

  it "does not count another database's migrations_paths (cache:) as primary's" do
    expect(points_for(fixture("sqlite.yml"))["production"].status).to eq(:inject)
  end

  it "falls back to the block's last key when database: is commented out" do
    content = <<~YAML
      default: &default
        adapter: sqlite3
      development:
        <<: *default
        database: storage/development.sqlite3
      test:
        <<: *default
        database: storage/test.sqlite3
      production:
        primary:
          <<: *default
          # database: path/to/persistent/storage/production.sqlite3
        cache:
          <<: *default
    YAML
    point = points_for(content)["production"]
    expect(point.status).to eq(:inject)
    expect(anchor_line(content, point)).to eq("    <<: *default\n")
  end

  it "counts an environment that reads the registry for other scopes (tenanted's planes) as wired" do
    content = <<~YAML
      development:
        global:
          database: storage/development.sqlite3
          migrations_paths: <%= Partitia::Support.migrations_paths[:global] %>
        tenant:
          database: storage/development/%{tenant}.sqlite3
          migrations_paths: <%= Partitia::Support.migrations_paths[:tenant] %>
          tenanted: true
    YAML
    point = described_class.new(content).points(%w[development]).first
    expect(point.status).to eq(:present)
  end

  it "accepts a url: in place of database:" do
    content = "production:\n  adapter: postgresql\n  url: <%= ENV['DATABASE_URL'] %>\n  pool: 5\n"
    point = described_class.new(content).points(%w[production]).first
    expect(point.line_index).to eq(2)
  end

  describe "where it cannot tell (manual)" do
    it "says so for a missing environment" do
      point = described_class.new("development:\n  database: d\n").points(%w[test]).first
      expect(point.status).to eq(:manual)
      expect(point.message).to include("no `test:` block", line)
    end

    it "says so for a multi-database block without primary:" do
      content = "production:\n  main:\n    database: a\n  cache:\n    database: b\n"
      point = described_class.new(content).points(%w[production]).first
      expect(point.status).to eq(:manual)
      expect(point.message).to include("primary:")
    end

    it "never rewrites a different migrations_paths the host set" do
      content = "development:\n  database: d\n  migrations_paths: db/other\n"
      point = described_class.new(content).points(%w[development]).first
      expect(point.status).to eq(:manual)
      expect(point.message).to include("already sets migrations_paths (line 3)")
    end

    it "says so for an empty environment" do
      point = described_class.new("development:\ntest:\n  database: t\n").points(%w[development]).first
      expect(point.status).to eq(:manual)
    end
  end
end
