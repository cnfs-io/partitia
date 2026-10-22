require "rails_helper"

# Single-tenant regression for the routing seam (Piece 5.2). The tenanted branch
# (returning the active tenant handle) is proven in Plan 004's integration dummy;
# here we lock down that single-tenant behavior is unchanged from Plan 001.
RSpec.describe "Partitia::Iam.current_account_handle" do
  it "returns an explicit host pin verbatim" do
    Partitia::Iam.config.account_handle = "pinned01"
    expect(Partitia::Iam.current_account_handle).to eq("pinned01")
  end

  it "mints a real handle (never a sentinel) and memoises it" do
    handle = Partitia::Iam.current_account_handle
    expect(handle).to match(Partitia::Iam::Handle::FORMAT)
    expect(Partitia::Iam.current_account_handle).to eq(handle)
  end
end
