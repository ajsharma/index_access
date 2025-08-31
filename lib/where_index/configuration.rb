module WhereIndex
  class Configuration
    attr_accessor :scope_prefix, :auto_generate, :included_models, :excluded_models

    def initialize
      @scope_prefix = "where_index_"
      @auto_generate = true
      @included_models = []
      @excluded_models = []
    end

    def include_model?(model_name)
      return false if excluded_models.include?(model_name)
      return true if included_models.empty?

      included_models.include?(model_name)
    end
  end
end
