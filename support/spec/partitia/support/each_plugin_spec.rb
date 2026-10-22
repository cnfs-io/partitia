require "spec_helper"

RSpec.describe "Partitia::Support.each_plugin" do
  # each_plugin is the sole place the "Rails first, then plugins, Engine-guarded"
  # walk lives. Rails is a module (not an Engine); plugins must be Engine
  # subclasses. Stub both so the walk can be exercised without a booted app.
  let(:rails)       { Module.new }
  let(:engine_base) { Class.new }
  let(:plugin_a)    { Class.new(engine_base) }
  let(:plugin_b)    { Class.new(engine_base) }

  before do
    stub_const("Rails", rails)
    stub_const("Rails::Engine", engine_base)
  end

  it "yields Rails first, then registered plugins in registration order" do
    allow(Partitia::Support).to receive(:plugins).and_return([ plugin_a, plugin_b ])

    expect { |b| Partitia::Support.each_plugin(&b) }
      .to yield_successive_args(rails, plugin_a, plugin_b)
  end

  it "raises on a non-Engine member of plugins" do
    allow(Partitia::Support).to receive(:plugins).and_return([ Class.new ])

    expect { Partitia::Support.each_plugin { |_| } }
      .to raise_error(/must be a Rails Engine/)
  end

  it "returns an Enumerator when called without a block" do
    allow(Partitia::Support).to receive(:plugins).and_return([ plugin_a ])

    expect(Partitia::Support.each_plugin).to be_a(Enumerator)
    expect(Partitia::Support.each_plugin.to_a).to eq([ rails, plugin_a ])
  end
end
