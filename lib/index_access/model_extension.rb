module IndexAccess
  module ModelExtension
    extend ActiveSupport::Concern

    included do
      after_initialize :generate_index_scopes, if: -> { IndexAccess.configuration.auto_generate }
    end

    class_methods do
      def generate_index_scopes!
        ScopeGenerator.new(self).generate_scopes
      end

      def index_scopes
        methods.grep(/^#{IndexAccess.configuration.scope_prefix}/)
      end
    end

    private

    def generate_index_scopes
      self.class.generate_index_scopes!
    end
  end
end
