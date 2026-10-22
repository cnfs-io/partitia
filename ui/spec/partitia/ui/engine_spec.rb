require "rails_helper"

RSpec.describe Partitia::Ui::Engine do
  it "registers with partitia-support (ARCHITECTURE §3, Q6)" do
    expect(Partitia::Support.plugins).to include(described_class)
  end

  it "puts its app/components on the Tailwind source paths" do
    expect(Partitia::Support.source_paths).to include(described_class.root.join("app/components").to_s)
  end

  # The host's app/components/ruby_ui (where `rails g ruby_ui:component` writes)
  # must be a collapsed RubyUI root like the engine's, or eager_load! expects
  # Components::RubyUI::Button::Button.
  it "eager loads the engine's and the host's RubyUI components" do
    expect { Rails.autoloaders.main.eager_load }.not_to raise_error
    expect(RubyUI::Button.ancestors).to include(RubyUI::Base)
  end

  it "lets the host's copy of a RubyUI component shadow the engine's" do
    file = RubyUI::Button.instance_method(:initialize).source_location.first

    expect(file).to eq(Rails.root.join("app/components/ruby_ui/button/button.rb").to_s)
  end
end
