module IndexAccess
  class Railtie < Rails::Railtie
    initializer "index_access.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        include IndexAccess::ModelExtension
      end
    end

    initializer "index_access.generate_scopes" do |_app|
      config.after_initialize do
        if IndexAccess.configuration.auto_generate
          Rails.application.eager_load!

          ActiveRecord::Base.descendants.each do |model|
            next unless model.table_exists?
            next unless IndexAccess.configuration.include_model?(model.name)

            model.generate_index_scopes!
          end
        end
      end
    end
  end
end
