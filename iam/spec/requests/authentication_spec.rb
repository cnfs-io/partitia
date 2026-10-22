require "rails_helper"

# Piece 6: Iam::Current + Iam::Authenticatable, driven through the dummy's
# ProbeController.
RSpec.describe "authentication", type: :request do
  it "treats a request with no session as anonymous" do
    get "/whoami"
    expect(response.body).to eq("anonymous")
  end

  it "resolves the principal from the session id" do
    principal = Iam::HumanPrincipal.create!(name: "alice")
    post "/sign_in", params: { id: principal.id }

    get "/whoami"
    expect(response.body).to eq("user:#{principal.id}")
  end

  it "treats a stale session id as anonymous (never an error)" do
    post "/sign_in", params: { id: 999_999 }
    get "/whoami"
    expect(response.body).to eq("anonymous")
  end

  describe "require_authentication" do
    it "halts an anonymous request with 401" do
      get "/protected"
      expect(response).to have_http_status(:unauthorized)
    end

    it "allows an authenticated request" do
      principal = Iam::HumanPrincipal.create!(name: "alice")
      post "/sign_in", params: { id: principal.id }

      get "/protected"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("ok")
    end
  end
end
