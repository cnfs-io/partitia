RSpec.describe Partitia::Dev::PryExt do
  describe ".drain_prompt_segments" do
    it "moves builder-registered segments into Prompt in order" do
      Partitia::Dev.console do |c|
        c.prompt_segment(color: :blue) { "one" }
        c.prompt_segment { "two" }
      end

      described_class.drain_prompt_segments

      registry = Partitia::Dev::PryExt::Prompt.segment_registry
      expect(registry.map { |s| s[:color] }).to eq([ :blue, nil ])
      expect(registry.map { |s| s[:body].call }).to eq(%w[one two])
    end
  end

  describe ".install_console_hook" do
    let(:main) { Object.new }

    before { stub_const("TOPLEVEL_BINDING", double("binding", receiver: main)) }
    after { Pry.config.hooks.delete_hook(:when_started, :partitia_console) }

    def start_console
      described_class.install_console_hook
      Pry.config.hooks.exec_hook(:when_started, nil, {}, nil)
    end

    it "wires every registry onto the console main" do
      cleanup = proc { :cleaned }
      Partitia::Dev.console do |c|
        c.namespace(DevFixtures::Chorus, "c")
        c.model(DevFixtures::Tenant, "t")
        c.command(:hello) { |who = "world"| "hi #{who}" }
        c.before_reset(&cleanup)
        c.reset_task "okf:sync"
      end

      start_console

      expect(main).to be_a(Partitia::Dev::PryExt::ConsoleMethods)
      expect(main.ca).to be(DevFixtures::Chorus::Agent)
      expect(main.cso).to be(DevFixtures::Chorus::Source)
      expect(main.tt).to be(DevFixtures::Tenant)
      expect(main.hello("acme")).to eq("hi acme")
      expect(main.project_reset_tasks).to eq([ "okf:sync" ])
      expect(main.instance_variable_get(:@before_project_reset_hooks)).to eq([ cleanup ])
    end
  end
end
