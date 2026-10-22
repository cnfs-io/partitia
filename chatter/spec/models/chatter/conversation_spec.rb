require "rails_helper"

module Chatter
  RSpec.describe Conversation, type: :model do
    describe "validations" do
      it "requires a name for group conversations" do
        conversation = build(:chatter_conversation, kind: :group, name: nil)
        expect(conversation).not_to be_valid
        expect(conversation.errors[:name]).to be_present
      end

      it "requires exactly two members for a direct conversation" do
        conversation = build(:chatter_conversation, :direct)
        conversation.memberships.build(participant: create(:person))

        expect(conversation).not_to be_valid
        expect(conversation.errors[:base]).to be_present
      end
    end

    describe ".find_or_create_direct" do
      it "creates a direct conversation between two heterogeneous participants" do
        person = create(:person)
        agent = create(:agent)

        conversation = described_class.find_or_create_direct(person, agent)

        expect(conversation).to be_direct
        expect(conversation.memberships.map(&:participant)).to contain_exactly(person, agent)
      end

      it "returns the existing conversation regardless of argument order" do
        person = create(:person)
        agent = create(:agent)

        first = described_class.find_or_create_direct(person, agent)
        second = described_class.find_or_create_direct(agent, person)

        expect(second).to eq(first)
        expect(described_class.where(kind: :direct).count).to eq(1)
      end

      it "does not collide with a third participant's direct conversations" do
        alice = create(:person)
        bob = create(:person)
        carol = create(:person)

        ab = described_class.find_or_create_direct(alice, bob)
        ac = described_class.find_or_create_direct(alice, carol)

        expect(ac).not_to eq(ab)
        expect(described_class.where(kind: :direct).count).to eq(2)
      end
    end
  end
end
