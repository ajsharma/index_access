module WhereIndex
  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      initializer "where_index.extend_active_record" do
        ActiveSupport.on_load(:active_record) do
          include WhereIndex::ModelExtension
        end
      end

      initializer "where_index.generate_scopes" do |_app|
        config.after_initialize do
          if WhereIndex.configuration.auto_generate
            Rails.application.eager_load!

            ActiveRecord::Base.descendants.each do |model|
              next unless model.table_exists?
              next unless WhereIndex.configuration.include_model?(model.name)

              model.generate_index_scopes!
            end
          end
        end
      end
    end
  end
end
