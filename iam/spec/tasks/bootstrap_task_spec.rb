require "rails_helper"
require "rake"

RSpec.describe "partitia:iam:bootstrap" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("partitia:iam:bootstrap") }

  def run_task
    task = Rake::Task["partitia:iam:bootstrap"]
    task.reenable
    stdout = nil
    expect { stdout = capture_stdout { task.invoke } }.to output(/partitia:iam:bootstrap: root/).to_stderr
    stdout
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "prints an unclaimed root's link token, then says claimed once root has a link" do
    out = run_task
    token = out[/^LINK_TOKEN=(\S+)$/, 1]

    expect(out).to start_with("ROOT=unclaimed\n")
    root = Partitia::Iam::HumanPrincipal.find_by_link_token(token)
    expect(root).to be_root

    root.identity_links.create!(issuer: "https://idp", subject: "sub-1")
    expect(run_task).to eq("ROOT=claimed\n")
  end
end
