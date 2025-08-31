require "active_record"
require "active_support"

require_relative "where_index/version"
require_relative "where_index/configuration"
require_relative "where_index/index_analyzer"
require_relative "where_index/scope_generator"
require_relative "where_index/model_extension"
require_relative "where_index/railtie" if defined?(Rails)

module WhereIndex
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
