RSpec.describe Partitia::Dev::PryExt::ShortcutPlanner do
  def codes(plans) = plans.to_h { |p| [ p[:klass], p[:prefix] ] }

  describe ".candidates" do
    it "single-capital names: first letter, then extend letter by letter" do
      expect(described_class.candidates("Agent")).to eq(%w[a ag age agen agent])
    end

    it "two-capital names: initials, then extend into the last word" do
      expect(described_class.candidates("AgentProfile"))
        .to eq(%w[ap apr apro aprof aprofi aprofil aprofile])
    end

    it "three-capital names: initials, then the 3rd capital, then extend the last word off the first two" do
      expect(described_class.candidates("ViewPortItem")).to eq(%w[vp vpi vpt vpte vptem])
    end

    it "treats digits as part of the word" do
      expect(described_class.candidates("V2")).to eq(%w[v v2])
    end
  end

  describe ".extend_word" do
    it "appends progressively longer prefixes of the tail" do
      expect(described_class.extend_word("ap", "rof")).to eq(%w[apr apro aprof])
      expect(described_class.extend_word("", "")).to eq([])
    end
  end

  describe ".assign_code" do
    it "returns the first unclaimed full shortcut" do
      expect(described_class.assign_code("c", "Agent", [])).to eq("ca")
      expect(described_class.assign_code("c", "Agent", %w[ca cag])).to eq("cage")
    end

    it "returns nil when the whole class name is exhausted" do
      expect(described_class.assign_code("c", "Ab", %w[ca cab])).to be_nil
    end
  end

  describe ".models_for" do
    it "finds concrete ActiveRecord models directly under the namespace" do
      expect(described_class.models_for(DevFixtures::Chorus)).to contain_exactly(
        DevFixtures::Chorus::Agent,
        DevFixtures::Chorus::AgentProfile,
        DevFixtures::Chorus::Artifact,
        DevFixtures::Chorus::Skill,
        DevFixtures::Chorus::Source
      )
    end

    it "skips nested models, abstract classes and non-models" do
      found = described_class.models_for(DevFixtures::Chorus)

      expect(found).not_to include(DevFixtures::Chorus::Source::Git, DevFixtures::Chorus::Base)
    end

    it "does not match sibling namespaces sharing a name prefix" do
      expect(described_class.models_for(DevFixtures::Chorus)).not_to include(DevFixtures::ChorusExtra::Thing)
      expect(described_class.models_for(DevFixtures::ChorusExtra)).to eq([ DevFixtures::ChorusExtra::Thing ])
    end

    it "returns [] for a namespace with no models" do
      expect(described_class.models_for(DevFixtures::Empty)).to eq([])
    end
  end

  describe ".plan" do
    it "assigns codes alphabetically within a namespace, first claim wins (README example)" do
      plans = described_class.plan([ { module: DevFixtures::Chorus, letter: "c" } ])

      expect(plans.map { |p| p[:prefix] }).to eq(%w[ca cap car cs cso])
      expect(codes(plans)).to eq(
        DevFixtures::Chorus::Agent => "ca",
        DevFixtures::Chorus::AgentProfile => "cap",
        DevFixtures::Chorus::Artifact => "car",
        DevFixtures::Chorus::Skill => "cs",
        DevFixtures::Chorus::Source => "cso"
      )
    end

    it "checks uniqueness across namespaces sharing a letter, in registration order" do
      plans = described_class.plan([
        { module: DevFixtures::Chorus, letter: "c" },
        { module: DevFixtures::Curry, letter: "c" }
      ])

      expect(codes(plans)).to include(DevFixtures::Chorus::Agent => "ca", DevFixtures::Curry::Agent => "cag",
                                      DevFixtures::Curry::Cart => "cc")
    end

    it "lets the earlier-registered namespace win the shorter code" do
      plans = described_class.plan([
        { module: DevFixtures::Curry, letter: "c" },
        { module: DevFixtures::Chorus, letter: "c" }
      ])

      expect(codes(plans)).to include(DevFixtures::Curry::Agent => "ca", DevFixtures::Chorus::Agent => "cag")
    end

    it "does not collide when letters differ" do
      plans = described_class.plan([
        { module: DevFixtures::Chorus, letter: "c" },
        { module: DevFixtures::Curry, letter: "k" }
      ])

      expect(codes(plans)).to include(DevFixtures::Chorus::Agent => "ca", DevFixtures::Curry::Agent => "ka")
    end

    it "plans explicit models after namespaces in the same collision set" do
      plans = described_class.plan(
        [ { module: DevFixtures::Chorus, letter: "c" } ],
        models: [ { klass: DevFixtures::Tenant, letter: "t" }, { klass: DevFixtures::Chorus::Agent, letter: "c" } ]
      )

      expect(plans.last(2)).to eq([
        { prefix: "tt", klass: DevFixtures::Tenant },
        { prefix: "cag", klass: DevFixtures::Chorus::Agent }
      ])
    end

    it "accepts symbol letters" do
      plans = described_class.plan([], models: [ { klass: DevFixtures::Tenant, letter: :t } ])

      expect(plans).to eq([ { prefix: "tt", klass: DevFixtures::Tenant } ])
    end

    it "honors pre-claimed codes without mutating the caller's array" do
      claimed = %w[tt]
      plans = described_class.plan([], models: [ { klass: DevFixtures::Tenant, letter: "t" } ], claimed: claimed)

      expect(plans).to eq([ { prefix: "tte", klass: DevFixtures::Tenant } ])
      expect(claimed).to eq(%w[tt])
    end

    it "skips a model whose code can't be made unique" do
      claimed = %w[t te ten tena tenan tenant].map { |c| "t#{c}" }
      plans = described_class.plan([], models: [ { klass: DevFixtures::Tenant, letter: "t" } ], claimed: claimed)

      expect(plans).to eq([])
    end

    it "is deterministic across runs" do
      registry = [ { module: DevFixtures::Chorus, letter: "c" }, { module: DevFixtures::Curry, letter: "c" } ]

      expect(described_class.plan(registry)).to eq(described_class.plan(registry))
    end
  end
end
