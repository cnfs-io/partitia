require "rails_helper"

RSpec.describe Partitia::Iam::Principal do
  describe "STI" do
    it "round-trips a subclass through the base class" do
      human = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      reloaded = Partitia::Iam::Principal.find(human.id)
      expect(reloaded).to be_a(Partitia::Iam::HumanPrincipal)
    end

    it "stores the subclass in the type column" do
      machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")
      expect(machine.type).to eq("Partitia::Iam::MachinePrincipal")
    end
  end

  describe "credentials association" do
    it "owns polymorphic credentials and cascades on destroy" do
      principal = create(:partitia_iam_machine_principal)
      credential = create(:partitia_iam_credential, owner: principal)

      expect(principal.credentials).to include(credential)
      expect { principal.destroy }.to change(Partitia::Iam::Credential, :count).by(-1)
    end
  end

  describe "#to_urn" do
    it "uses the AWS-style resource_type per subclass and the current handle" do
      Partitia::Iam.config.account_handle = "handle01"
      human = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")

      expect(human.to_urn).to eq("urn:partitia:iam::handle01:user/#{human.id}")
      expect(machine.to_urn).to eq("urn:partitia:iam::handle01:machine/#{machine.id}")
    ensure
      Partitia::Iam.config.account_handle = nil
    end

    it "is findable by URN, scoped to the resource type" do
      human = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      expect(Partitia::Iam::HumanPrincipal.find_by_urn(human.to_urn)).to eq(human)
      # A machine URN must not resolve through the human scope.
      machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")
      expect(Partitia::Iam::HumanPrincipal.find_by_urn(machine.to_urn)).to be_nil
    end

    it "does not resolve a URN from another partition, service or account" do
      human = Partitia::Iam::HumanPrincipal.create!(name: "alice")
      parsed = Partitia::Iam::Urn.parse(human.to_urn)
      build = ->(**over) { Partitia::Iam::Urn.build(**{ account: parsed.account, resource_type: parsed.resource_type, resource_id: parsed.resource_id }.merge(over)) }

      expect(Partitia::Iam::HumanPrincipal.find_by_urn(build.call)).to eq(human)
      expect(Partitia::Iam::HumanPrincipal.find_by_urn(build.call(partition: "other"))).to be_nil
      expect(Partitia::Iam::HumanPrincipal.find_by_urn(build.call(account: "elsewhere"))).to be_nil
      expect(Partitia::Iam::HumanPrincipal.find_by_urn(human.to_urn.sub(":iam:", ":s3:"))).to be_nil
    end
  end

  it "requires a name" do
    expect(Partitia::Iam::HumanPrincipal.new.tap(&:valid?).errors[:name]).to be_present
  end
end
