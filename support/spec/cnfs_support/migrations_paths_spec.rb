require "spec_helper"
require "tmpdir"
require "fileutils"
require "pathname"

RSpec.describe "CnfsSupport.set_migrations_paths_from" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  end

  # migrations_paths is process-global — reset it so accumulation never leaks
  # between examples.
  before do
    CnfsSupport.migrations_paths.clear
    FileUtils.mkdir_p(@root.join("db/migrate"))
  end

  it "collects an existing db/migrate under the :primary key" do
    CnfsSupport.set_migrations_paths_from(double(root: @root))

    expect(CnfsSupport.migrations_paths[:primary]).to eq([ @root.join("db/migrate").to_s ])
  end

  it "is idempotent — the same plugin twice yields the path once" do
    plugin = double(root: @root)

    CnfsSupport.set_migrations_paths_from(plugin)
    CnfsSupport.set_migrations_paths_from(plugin)

    expect(CnfsSupport.migrations_paths[:primary]).to eq([ @root.join("db/migrate").to_s ])
  end

  it "skips a plugin whose db/migrate does not exist" do
    FileUtils.rm_rf(@root.join("db"))

    CnfsSupport.set_migrations_paths_from(double(root: @root))

    expect(CnfsSupport.migrations_paths[:primary]).to eq([])
  end
end
