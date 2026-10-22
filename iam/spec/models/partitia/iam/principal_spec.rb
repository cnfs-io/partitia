require "rails_helper"

RSpec.describe Iam::Principal do
  describe "STI" do
    it "round-trips a subclass through the base class" do
      human = Iam::HumanPrincipal.create!(name: "alice")
      reloaded = Iam::Principal.find(human.id)
      expect(reloaded).to be_a(Iam::HumanPrincipal)
    end

    it "stores the subclass in the type column" do
      machine = Iam::MachinePrincipal.create!(name: "worker")
      expect(machine.type).to eq("Iam::MachinePrincipal")
    end
  end

  describe "credentials association" do
    it "owns polymorphic credentials and cascades on destroy" do
      principal = create(:iam_machine_principal)
      credential = create(:iam_credential, owner: principal)

      expect(principal.credentials).to include(credential)
      expect { principal.destroy }.to change(Iam::Credential, :count).by(-1)
    end
  end

  describe "#to_urn" do
    it "uses the AWS-style resource_type per subclass and the current handle" do
      Iam.config.account_handle = "handle01"
      human = Iam::HumanPrincipal.create!(name: "alice")
      machine = Iam::MachinePrincipal.create!(name: "worker")

      expect(human.to_urn).to eq("urn:cnfs:iam::handle01:user/#{human.id}")
      expect(machine.to_urn).to eq("urn:cnfs:iam::handle01:machine/#{machine.id}")
    ensure
      Iam.config.account_handle = nil
    end

    it "is findable by URN, scoped to the resource type" do
      human = Iam::HumanPrincipal.create!(name: "alice")
      expect(Iam::HumanPrincipal.find_by_urn(human.to_urn)).to eq(human)
      # A machine URN must not resolve through the human scope.
      machine = Iam::MachinePrincipal.create!(name: "worker")
      expect(Iam::HumanPrincipal.find_by_urn(machine.to_urn)).to be_nil
    end
  end

  it "requires a name" do
    expect(Iam::HumanPrincipal.new.tap(&:valid?).errors[:name]).to be_present
  end
end
