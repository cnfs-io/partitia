# frozen_string_literal: true

module Views
end

module Components
  extend Phlex::Kit
end

Rails.autoloaders.main.push_dir(
  Partitia::Ui::Engine.root.join("app/views"), namespace: Views
)

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/views"), namespace: Views
)

Rails.autoloaders.main.push_dir(
  Partitia::Ui::Engine.root.join("app/components"), namespace: Components
)

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/components"), namespace: Components
)
