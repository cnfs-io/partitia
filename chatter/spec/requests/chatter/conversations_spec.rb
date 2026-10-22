require "rails_helper"

RSpec.describe "Chatter::Conversations", type: :request do
  let(:alice) { create(:person, name: "Alice") }
  let(:bob) { create(:person, name: "Bob") }

  describe "GET /chatter/conversations/:id" do
    it "lets a member view the conversation" do
      conversation = Chatter::Conversation.find_or_create_direct(alice, bob)
      create(:chatter_message, conversation: conversation, sender: alice, content: "Hello Bob")
      sign_in alice

      get "/chatter/conversations/#{conversation.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hello Bob")
    end

    it "forbids a non-member from viewing the conversation" do
      conversation = Chatter::Conversation.find_or_create_direct(alice, bob)
      carol = create(:person, name: "Carol")
      sign_in carol

      get "/chatter/conversations/#{conversation.id}"

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /chatter/conversations" do
    it "finds or creates a direct conversation" do
      sign_in alice

      expect {
        post "/chatter/conversations", params: { kind: "direct", participant_gid: bob.to_gid.to_s }
      }.to change(Chatter::Conversation, :count).by(1)

      conversation = Chatter::Conversation.last
      expect(conversation).to be_direct
      expect(conversation.participants).to contain_exactly(alice, bob)
      expect(response).to redirect_to("/chatter/conversations/#{conversation.id}")
    end

    it "creates a group with the creator as owner" do
      carol = create(:person, name: "Carol")
      sign_in alice

      post "/chatter/conversations", params: {
        kind: "group", name: "Project", member_gids: [ bob.to_gid.to_s, carol.to_gid.to_s ]
      }

      conversation = Chatter::Conversation.last
      expect(conversation).to be_group
      expect(conversation.name).to eq("Project")
      expect(conversation.participants).to contain_exactly(alice, bob, carol)
      expect(conversation.memberships.find_by(participant: alice)).to be_owner
    end
  end
end
