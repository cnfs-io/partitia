# Test helper for the dummy's fake auth: "become" a participant by posting its
# GlobalID to the host session route, exactly as the switcher does.
module AuthenticationHelpers
  def sign_in(participant)
    post "/session", params: { gid: participant.to_gid.to_s }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
