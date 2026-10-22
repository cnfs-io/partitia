require "rails_helper"

RSpec.describe "Chatter::Messages", type: :request do
  include ActiveJob::TestHelper

  let(:alice) { create(:person, name: "Alice") }
  let(:bob) { create(:person, name: "Bob") }
  let(:conversation) { Chatter::Conversation.find_or_create_direct(alice, bob) }

  describe "POST /chatter/conversations/:conversation_id/messages" do
    it "persists a message sent by a member" do
      sign_in alice

      expect {
        post "/chatter/conversations/#{conversation.id}/messages",
          params: { message: { content: "Hi Bob" } }
      }.to change(conversation.messages, :count).by(1)

      message = conversation.messages.last
      expect(message.content).to eq("Hi Bob")
      expect(message.sender).to eq(alice)
    end

    it "forbids a non-member from posting" do
      carol = create(:person, name: "Carol")
      sign_in carol

      expect {
        post "/chatter/conversations/#{conversation.id}/messages",
          params: { message: { content: "intruding" } }
      }.not_to change(Chatter::Message, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "broadcasts the message to the conversation stream" do
      sign_in alice

      # broadcasts_to enqueues the broadcast as a job; perform it so the broadcast
      # actually reaches the stream. Turbo broadcasts to the conversation's
      # to_gid_param stream — the raw name `turbo_stream_from @conversation` resolves to.
      stream = conversation.to_gid_param

      expect {
        perform_enqueued_jobs do
          post "/chatter/conversations/#{conversation.id}/messages",
            params: { message: { content: "Broadcasted" } }
        end
      }.to have_broadcasted_to(stream)
    end
  end
end
