require "spec_helper"
require "tmpdir"
require "fileutils"
require "pathname"

RSpec.describe "CnfsSupport.set_source_paths_from" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  end

  # source_paths is process-global — reset it so accumulation never leaks
  # between examples.
  before { CnfsSupport.source_paths.clear }

  it "collects app/views and app/helpers that exist, skipping app/components that does not" do
    FileUtils.mkdir_p(@root.join("app/views"))
    FileUtils.mkdir_p(@root.join("app/helpers"))

    CnfsSupport.set_source_paths_from(double(root: @root))

    expect(CnfsSupport.source_paths).to contain_exactly(
      @root.join("app/views").to_s,
      @root.join("app/helpers").to_s
    )
  end

  it "records absolute paths" do
    FileUtils.mkdir_p(@root.join("app/views"))

    CnfsSupport.set_source_paths_from(double(root: @root))

    expect(CnfsSupport.source_paths).to all(satisfy { |p| Pathname.new(p).absolute? })
  end

  it "is idempotent — the same plugin twice yields each path once" do
    FileUtils.mkdir_p(@root.join("app/views"))
    plugin = double(root: @root)

    CnfsSupport.set_source_paths_from(plugin)
    CnfsSupport.set_source_paths_from(plugin)

    expect(CnfsSupport.source_paths.count(@root.join("app/views").to_s)).to eq(1)
  end
end
