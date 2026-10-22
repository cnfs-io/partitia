module Chatter
  class ConversationsController < ApplicationController
    before_action :require_participant
    before_action :set_conversation, only: :show

    def index
      @conversations = current_participant.conversations.includes(:memberships)
      @direct_conversations = @conversations.select(&:direct?)
      @group_conversations = @conversations.select(&:group?)
      @participants = other_participants
    end

    def show
      head :forbidden and return unless member?(@conversation)

      @messages = @conversation.messages
      @message = Message.new
    end

    def create
      conversation =
        if params[:kind] == "direct"
          start_direct
        else
          start_group
        end

      if conversation&.persisted?
        redirect_to conversation
      else
        redirect_to conversations_path, alert: "Could not start the conversation."
      end
    end

    private

    def set_conversation
      @conversation = Conversation.find(params[:id])
    end

    def member?(conversation)
      conversation.memberships.exists?(
        participant_type: current_participant.class.polymorphic_name,
        participant_id: current_participant.id
      )
    end

    def start_direct
      other = GlobalID::Locator.locate(params[:participant_gid])
      return unless other

      Conversation.find_or_create_direct(current_participant, other)
    end

    def start_group
      members = Array(params[:member_gids]).filter_map { |gid| GlobalID::Locator.locate(gid) }
      members.unshift(current_participant)
      members.uniq!

      conversation = Conversation.new(kind: :group, name: params[:name])
      members.each_with_index do |participant, index|
        conversation.memberships.build(
          participant: participant,
          role: index.zero? ? :owner : :member
        )
      end
      conversation.save
      conversation
    end

    # Participants the current participant could start a conversation with.
    # The engine has no host model registry, so the host exposes the candidates.
    def other_participants
      Chatter.participant_candidates.call.reject { |p| p == current_participant }
    end

    def require_participant
      return if current_participant

      render plain: "No current participant. Use the switcher to pick one.", status: :forbidden
    end
  end
end
