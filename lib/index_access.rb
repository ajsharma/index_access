require "active_record"
require "active_support"

require_relative "index_access/version"
require_relative "index_access/configuration"
require_relative "index_access/index_analyzer"
require_relative "index_access/scope_generator"
require_relative "index_access/model_extension"
require_relative "index_access/railtie" if defined?(Rails)

module IndexAccess
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
