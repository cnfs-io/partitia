require "rails/generators/base"

module CnfsTenanted
  module Generators
    # Ejects (copies) the engine's views for a resource into the host app, so
    # the app owns and can customize them. This is the phase-2 customization
    # path: in phase 1 the engine's views render directly (Rails view
    # resolution finds them); once ejected, the host's copies take precedence.
    #
    #   bin/rails generate cnfs_tenanted:views tenants
    #   bin/rails generate cnfs_tenanted:views accounts
    #   bin/rails generate cnfs_tenanted:views            # both
    #
    class ViewsGenerator < Rails::Generators::Base
      RESOURCES = %w[ tenants accounts ].freeze

      argument :resource, type: :string, required: false,
               desc: "Which views to eject: tenants, accounts, or omit for all"

      desc "Copy cnfs_tenanted views into the host app for customization."

      def copy_views
        targets = resource ? [ resource ] : RESOURCES

        targets.each do |name|
          unless RESOURCES.include?(name)
            say_status :error, "Unknown resource #{name.inspect}. Known: #{RESOURCES.join(', ')}", :red
            next
          end

          source = engine_views_path.join(name)
          Dir.glob(source.join("**", "*")).select { |f| File.file?(f) }.each do |file|
            rel = Pathname.new(file).relative_path_from(engine_views_path)
            copy_file file, "app/views/#{rel}"
          end
        end
      end

      private

      def engine_views_path
        @engine_views_path ||= Pathname.new(
          File.expand_path("../../../../app/views", __dir__)
        )
      end
    end
  end
end
