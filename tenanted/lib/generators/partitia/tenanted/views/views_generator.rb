require "rails/generators/base"

module Partitia
  module Tenanted
    module Generators
      # Ejects (copies) the engine's views for a resource into the host app, so
      # the app owns and can customize them. Until then the engine's views render
      # directly; once ejected, the host's copies take precedence.
      #
      #   bin/rails generate partitia:tenanted:views tenants
      #   bin/rails generate partitia:tenanted:views tenant_not_found
      #   bin/rails generate partitia:tenanted:views            # all
      class ViewsGenerator < Rails::Generators::Base
        RESOURCES = %w[ tenants tenant_not_found ].freeze

        source_root File.expand_path("../../../../../app/views", __dir__)

        argument :resource, type: :string, required: false,
                 desc: "Which views to eject: #{RESOURCES.join(', ')}, or omit for all"

        desc "Copy partitia-tenanted views into the host app for customization."

        def check_resource
          return if resource.nil? || RESOURCES.include?(resource)

          raise Thor::Error, "Unknown resource #{resource.inspect}. Known: #{RESOURCES.join(', ')}"
        end

        def copy_views
          (resource ? [ resource ] : RESOURCES).each do |name|
            directory name, "app/views/#{name}"
          end
        end
      end
    end
  end
end
