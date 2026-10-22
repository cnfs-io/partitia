require "rails_helper"
require "tmpdir"
require "generators/chatter/install/install_generator"

RSpec.describe Chatter::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  def run_generator
    described_class.start([], destination_root: @dir, shell: Thor::Base.shell.new)
  end

  def read(rel) = File.read(File.join(@dir, rel))

  def scaffold_app
    FileUtils.mkdir_p(File.join(@dir, "config"))
    File.write(File.join(@dir, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  before { scaffold_app }

  it "mounts the engine in the host routes" do
    run_generator
    expect(read("config/routes.rb")).to include(%(mount Chatter::Engine => "/chatter"))
  end

  it "is safe to re-run — no duplicate mount line" do
    run_generator
    run_generator
    routes = read("config/routes.rb")
    expect(routes.scan(%(mount Chatter::Engine)).size).to eq(1)
  end
end
