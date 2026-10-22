RSpec.describe Partitia::Dev::Builder do
  subject(:builder) { described_class.new }

  describe "#namespace" do
    it "registers the module with a stringified letter" do
      builder.namespace(DevFixtures::Chorus, :c)

      expect(Partitia::Dev.namespaces).to eq([ { module: DevFixtures::Chorus, letter: "c" } ])
    end
  end

  describe "#model" do
    it "registers a single class with a stringified letter" do
      builder.model(DevFixtures::Tenant, :t)

      expect(Partitia::Dev.models).to eq([ { klass: DevFixtures::Tenant, letter: "t" } ])
    end
  end

  describe "#command" do
    it "registers a symbolized name and the block" do
      body = proc { |name = ""| name }
      builder.command("vst", &body)

      expect(Partitia::Dev.commands).to eq([ { name: :vst, body: body } ])
    end

    it "raises without a block" do
      expect { builder.command(:vst) }.to raise_error(ArgumentError, /command :vst requires a block/)
      expect(Partitia::Dev.commands).to be_empty
    end
  end

  describe "#prompt_segment" do
    it "stores color and block as inert data" do
      body = proc { "acme" }
      builder.prompt_segment(color: :blue, &body)

      expect(Partitia::Dev.prompt_segments).to eq([ { color: :blue, body: body } ])
    end

    it "defaults color to nil" do
      builder.prompt_segment { "x" }

      expect(Partitia::Dev.prompt_segments.first[:color]).to be_nil
    end

    it "does not touch the Prompt module at registration time" do
      builder.prompt_segment { "x" }

      expect(Partitia::Dev::PryExt::Prompt.segment_registry).to be_empty
    end

    it "raises without a block" do
      expect { builder.prompt_segment(color: :red) }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  describe "#before_reset" do
    it "registers blocks in order" do
      first = proc { 1 }
      second = proc { 2 }
      builder.before_reset(&first).before_reset(&second)

      expect(Partitia::Dev.before_resets).to eq([ first, second ])
    end

    it "raises without a block" do
      expect { builder.before_reset }.to raise_error(ArgumentError, /requires a block/)
    end
  end

  describe "#reset_task" do
    it "stringifies the task name" do
      builder.reset_task(:"okf:sync")

      expect(Partitia::Dev.reset_tasks).to eq([ "okf:sync" ])
    end
  end

  it "is chainable across every contribution kind" do
    result = builder
      .namespace(DevFixtures::Chorus, "c")
      .model(DevFixtures::Tenant, "t")
      .command(:hello) { "hi" }
      .prompt_segment(color: :blue) { "seg" }
      .before_reset { nil }
      .reset_task("my_gem:sync")

    expect(result).to be(builder)
    expect(Partitia::Dev.namespaces.size).to eq(1)
    expect(Partitia::Dev.models.size).to eq(1)
    expect(Partitia::Dev.commands.size).to eq(1)
    expect(Partitia::Dev.prompt_segments.size).to eq(1)
    expect(Partitia::Dev.before_resets.size).to eq(1)
    expect(Partitia::Dev.reset_tasks.size).to eq(1)
  end
end
