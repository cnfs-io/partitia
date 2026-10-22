# app/models/concerns/partitia/support/yaml_serializable.rb
module Partitia
  module Support
    module YamlSerializable
      extend ActiveSupport::Concern

      class_methods do
        # Dump all rows (or a scope) to a YAML file.
        #   User.dump_to_yaml
        #   User.where(active: true).dump_to_yaml("tmp/active_users.yml")
        def dump_to_yaml(path = nil)
          path ||= default_yaml_path
          scope = current_scope || all

          records = scope.order(primary_key).map(&:attributes)
          File.write(path, YAML.dump(records))
          path
        end

        # Load rows back from a YAML file.
        # By default upserts on the primary key so it's idempotent.
        #   User.load_from_yaml
        #   User.load_from_yaml("tmp/active_users.yml", mode: :insert)
        #
        # mode:
        #   :upsert  -> insert or update on PK conflict (default)
        #   :insert  -> insert_all, skips PK conflicts
        #   :replace -> delete_all then insert (full restore)
        def load_from_yaml(path = nil, mode: :upsert)
          path ||= default_yaml_path
          rows = YAML.load_file(path, permitted_classes: yaml_permitted_classes, aliases: true)
          return 0 if rows.blank?

          transaction do
            case mode
            when :replace
              delete_all
              insert_all(rows)
            when :insert
              insert_all(rows)
            when :upsert
              upsert_all(rows, unique_by: primary_key.to_sym)
            else
              raise ArgumentError, "unknown mode: #{mode.inspect}"
            end
          end

          rows.size
        end

        private

        def default_yaml_path
          # TODO: should respect the tenant if Tenanted
          # maybe a path method to storage?
          Rails.root.join("db", "seeds", "#{table_name}.yml").to_s
        end

        # Types that may appear in serialized attributes.
        def yaml_permitted_classes
          [ Symbol, Time, Date, DateTime, ActiveSupport::TimeWithZone,
           ActiveSupport::TimeZone, BigDecimal ]
        end
      end
    end
  end
end
