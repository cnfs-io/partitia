require "rails_helper"

RSpec.describe Partitia::Iam::Account do
  describe "singleton enforcement" do
    it ".instance is idempotent and always the id=1 row" do
      first = described_class.instance(name: "Acme")
      second = described_class.instance(name: "Ignored")

      expect(first.id).to eq(described_class::SINGLETON_ID)
      expect(second).to eq(first)
      expect(described_class.count).to eq(1)
      expect(first.reload.name).to eq("Acme")   # attrs only applied on create
    end

    it "rejects a second row at the model layer (id inclusion)" do
      described_class.instance(name: "Acme")
      other = described_class.new(id: 2, name: "Other")
      expect(other).not_to be_valid
      expect(other.errors[:id]).to be_present
    end

    it "rejects a second row at the DB layer (CHECK id = 1)" do
      described_class.instance(name: "Acme")
      expect {
        described_class.new(id: 2, name: "Other").save!(validate: false)
      }.to raise_error(ActiveRecord::StatementInvalid, /constraint/i)
    end
  end

  describe "validations" do
    it "requires a name" do
      expect(described_class.new(id: 1).tap(&:valid?).errors[:name]).to be_present
    end
  end

  describe "#destroy" do
    it "raises ReadOnlyRecord — singletons are never destroyed" do
      account = described_class.instance(name: "Acme")
      expect { account.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(described_class.count).to eq(1)
    end
  end

  it "has a working factory" do
    expect(create(:partitia_iam_account)).to be_persisted
  end
end
