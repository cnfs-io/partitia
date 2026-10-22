require "rake"

RSpec.describe Partitia::Dev::PryExt::ConsoleMethods do
  subject(:console) { Object.new.extend(described_class) }

  let(:relation) { double("relation") }
  let(:klass) { double("Bundle", all: relation) }

  before { console.def_model_shortcuts("ob", klass) }

  describe "#def_model_shortcuts" do
    it "defines the family on the console's singleton only" do
      expect(console).to respond_to(:ob, :oba, :obc, :obf, :obf!, :obl, :obl!, :obp)
      expect(Object.new.extend(described_class)).not_to respond_to(:ob)
    end

    it "ob returns the class, oba .all, obp .all.pluck(*args)" do
      allow(relation).to receive(:pluck).with(:name, :age).and_return([ [ "x", 1 ] ])

      expect(console.ob).to be(klass)
      expect(console.oba).to be(relation)
      expect(console.obp(:name, :age)).to eq([ [ "x", 1 ] ])
    end
  end

  describe "memoized finders" do
    it "obf memoizes per id" do
      allow(klass).to receive(:find) { |id| "record-#{id}" }

      expect(console.obf(3)).to eq("record-3")
      expect(console.obf(3)).to be(console.obf(3))
      expect(console.obf(4)).to eq("record-4")
      expect(klass).to have_received(:find).with(3).once
      expect(klass).to have_received(:find).with(4).once
    end

    it "obf with no id memoizes .first" do
      allow(klass).to receive(:first).and_return("first")

      2.times { expect(console.obf).to eq("first") }
      expect(klass).to have_received(:first).once
    end

    it "memoizes nil results too" do
      allow(klass).to receive(:last).and_return(nil)

      2.times { console.obl }
      expect(klass).to have_received(:last).once
    end

    it "obf! always refetches and overwrites the memo" do
      allow(klass).to receive(:find).and_return("old", "new")

      console.obf(3)
      expect(console.obf!(3)).to eq("new")
      expect(console.obf(3)).to eq("new")
      expect(klass).to have_received(:find).twice
    end

    it "obl memoizes and obl! refreshes" do
      allow(klass).to receive(:last).and_return("a", "b")

      expect(console.obl).to eq("a")
      expect(console.obl).to eq("a")
      expect(console.obl!).to eq("b")
      expect(console.obl).to eq("b")
    end
  end

  describe "obc" do
    before { allow(klass).to receive(:last).and_return("old-last", "new-last") }

    it "creates with attributes and busts the obl memo when persisted" do
      record = double("record", persisted?: true)
      allow(klass).to receive(:create).with({ name: "x" }).and_return(record)

      console.obl
      expect(console.obc(name: "x")).to be(record)
      expect(console.obl).to eq("new-last")
    end

    it "keeps the obl memo when the create fails" do
      allow(klass).to receive(:create).with({}).and_return(double("record", persisted?: false))

      console.obl
      console.obc
      expect(console.obl).to eq("old-last")
    end

    it "leaves obf memos alone" do
      allow(klass).to receive_messages(find: "found", create: double("record", persisted?: true))

      console.obf(1)
      console.obc
      console.obf(1)
      expect(klass).to have_received(:find).once
    end
  end

  describe "#clear!" do
    before { allow(klass).to receive_messages(find: "f", last: "l") }

    it "clears every memo" do
      console.obf(1)
      console.obl

      expect(console.clear!).to be_nil
      console.obf(1)
      console.obl
      expect(klass).to have_received(:find).twice
      expect(klass).to have_received(:last).twice
    end

    it "clears one family, by symbol or string" do
      console.obf(1)
      console.obl

      console.clear!("obf")
      console.obf(1)
      console.obl
      expect(klass).to have_received(:find).twice
      expect(klass).to have_received(:last).once
    end
  end

  describe "#shortcuts" do
    before do
      console.def_model_shortcuts("cap", double("AgentProfile", to_s: "Chorus::AgentProfile"))
      console.def_model_shortcuts("ca", double("Agent", to_s: "Chorus::Agent"))
      allow(klass).to receive(:to_s).and_return("Okf::Bundle")
    end

    it "prints every family sorted and aligned, returning nil" do
      result = nil
      expect { result = console.shortcuts }
        .to output("ca   Chorus::Agent\ncap  Chorus::AgentProfile\nob   Okf::Bundle\n").to_stdout
      expect(result).to be_nil
    end

    it "filters by prefix" do
      expect { console.shortcuts("ca") }.to output("ca   Chorus::Agent\ncap  Chorus::AgentProfile\n").to_stdout
      expect { console.shortcuts(:o) }.to output("ob  Okf::Bundle\n").to_stdout
      expect { console.shortcuts("zz") }.to output("").to_stdout
    end
  end

  describe "#install_reload_memo_clear!" do
    let(:reloads) { [] }

    before do
      log = reloads
      console.define_singleton_method(:reload!) { |*| log << :reloaded }
      allow(klass).to receive(:last).and_return("a", "b")
    end

    it "makes reload! (and r) clear memos and still reload, idempotently" do
      2.times { console.install_reload_memo_clear! }

      console.obl
      console.reload!
      expect(console.obl).to eq("b")
      console.r
      expect(reloads).to eq(%i[reloaded reloaded])
    end
  end

  describe "project reset registration" do
    it "accumulates before_project_reset hooks and reset tasks" do
      console.before_project_reset { 1 }
      console.before_project_reset # no block: ignored
      console.project_reset_tasks << "okf:sync"

      expect(console.instance_variable_get(:@before_project_reset_hooks).size).to eq(1)
      expect(console.project_reset_tasks).to eq([ "okf:sync" ])
    end
  end

  describe "#deep_reenable" do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = original
    end

    it "re-enables a task and its prerequisites recursively" do
      runs = []
      Rake::Task.define_task(:leaf) { runs << :leaf }
      Rake::Task.define_task(mid: :leaf) { runs << :mid }
      Rake::Task.define_task(top: :mid) { runs << :top }

      Rake::Task[:top].invoke
      Rake::Task[:top].invoke
      expect(runs).to eq(%i[leaf mid top])

      console.deep_reenable("top")
      Rake::Task[:top].invoke
      expect(runs).to eq(%i[leaf mid top leaf mid top])
    end

    it "ignores unknown tasks" do
      expect(console.deep_reenable("nope:missing")).to be_nil
    end
  end
end
