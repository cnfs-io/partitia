# cnfs_ui/lib/generators/cnfs_ui/component_generator.rb
require "rails/generators"

module CnfsUi
  module Generators
    class Component < Rails::Generators::Base
      argument :component_name, type: :string, desc: "The name of the RubyUI component to eject"

      def call_ruby_ui_generator
        # 1. Temporarily swap the engine source root path to target your engine
        original_root = Rails::Generators::ComponentGenerator.source_root if defined?(Rails::Generators::ComponentGenerator)

        # 2. Force the generation target destination directly to your engine directory
        destination_path = CnfsUi::Engine.root # .join("app/components/cnfs_ui")
        # binding.pry

        # 3. Invoke the core ruby_ui generator targeting your engine folder
        Rails::Generators.invoke("ruby_ui:component", [ component_name ], destination_root: destination_path)
      end
    end
  end
end
