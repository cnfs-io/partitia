module RubyUI
  extend Phlex::Kit
end

# Allow using RubyUI instead RubyUi
Rails.autoloaders.main.inflector.inflect(
  "ruby_ui" => "RubyUI"
)

# RubyUI components live in app/components/ruby_ui/<name>/<name>.rb, both in this
# engine and in the host (where `rails g ruby_ui:component` puts them). Each such
# directory is its own RubyUI root with the per-component folders collapsed, so
# RubyUI::Button (not Components::RubyUI::Button::Button) is what Zeitwerk expects.
# Without this for the host's directory, the host's app/components root (namespace
# Components) claims it and eager_load! fails on the first component.
#
# The host is pushed first so its copy of a component shadows the engine's.
[ Rails.root, Partitia::Ui::Engine.root ].map { |root| root.join("app/components/ruby_ui") }.uniq.each do |dir|
  next unless dir.directory?

  Rails.autoloaders.main.push_dir(dir, namespace: RubyUI)
  Rails.autoloaders.main.collapse(dir.join("*"))
end
