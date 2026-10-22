module Chatter
  class MessagesController < ApplicationController
    before_action :require_participant
    before_action :set_conversation

    def create
      head :forbidden and return unless member?(@conversation)

      @message = @conversation.messages.build(message_params.merge(sender: current_participant))

      if @message.save
        # Delivery to every subscriber (including the sender, who is also
        # subscribed) happens via the model's broadcasts_to. Just redirect back.
        respond_to do |format|
          format.turbo_stream { head :no_content }
          format.html { redirect_to @conversation }
        end
      else
        redirect_to @conversation, alert: "Message can't be blank."
      end
    end

    private

    def set_conversation
      @conversation = Conversation.find(params[:conversation_id])
    end

    def member?(conversation)
      conversation.memberships.exists?(
        participant_type: current_participant.class.polymorphic_name,
        participant_id: current_participant.id
      )
    end

    def message_params
      params.require(:message).permit(:content)
    end

    def require_participant
      head :forbidden unless current_participant
    end
  end
end
