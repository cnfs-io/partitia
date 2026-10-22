require "open3"
require "rbconfig"

# pry-byebug patches Pry and byebug, so it must load only with the console
# wiring (pry_ext, required from the Railtie's `console` block), never because
# the gem was required. This process already loaded pry_ext (spec_helper), so
# the "not loaded" side is checked in a fresh Ruby.
RSpec.describe "loading partitia-dev" do
  def loaded_after(requires)
    script = requires.map { |r| "require #{r.inspect}" }.join(";") +
             ";print [defined?(Pry), defined?(PryByebug)].map(&:inspect).join(',')"
    lib = File.expand_path("../../../lib", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)
    raise "subprocess failed: #{err}" unless status.success?

    out.split(",")
  end

  it "does not load pry or pry-byebug when only the gem is required" do
    expect(loaded_after(%w[partitia/dev])).to eq(%w[nil nil])
  end

  it "loads pry-byebug with the console wiring" do
    expect(loaded_after(%w[partitia/dev partitia/dev/pry_ext])).to eq(%w["constant" "constant"])
  end
end

RSpec.describe Partitia::Dev::PryExt, ".setup! stepping aliases" do
  after do
    Pry.config.hooks.delete_hook(:when_started, :partitia_console)
  end

  it "aliases n/s/c/f to pry-byebug's next/step/continue/finish" do
    commands = Pry::CommandSet.new(Pry.commands)
    allow(Pry).to receive(:commands).and_return(commands)

    described_class.setup!

    { "n" => "next", "s" => "step", "c" => "continue", "f" => "finish" }.each do |short, long|
      expect(commands.find_command(short)&.description).to eq("Alias for `#{long}`")
    end
  end
end
