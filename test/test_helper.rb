$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
ENV["RAILS_ENV"] ||= "test"

require "dotenv"
Dotenv.load(".env.test.local", ".env.local", ".env")

# Setup minimal Rails-like environment for testing
require "active_record"
require "pg"
# Mock Rails module with schema cache configuration
module Rails
  def self.respond_to?(method)
    method == :application
  end

  def self.application
    @application ||= Application.new
  end

  class Application
    attr_accessor :config

    def initialize
      @config = Config.new
    end
  end

  class Config
    attr_accessor :active_record

    def initialize
      @active_record = ActiveRecordConfig.new
    end
  end

  class ActiveRecordConfig
    attr_accessor :use_schema_cache_dump

    def initialize
      # This can be overridden in tests
      @use_schema_cache_dump = ENV.fetch("USE_SCHEMA_CACHE", "true") == "true"
    end
  end
end

require "index_access"
require "minitest/autorun"

# Setup PostgreSQL database for testing
ActiveRecord::Base.establish_connection(
  ENV.fetch("DATABASE_URL")
)

# Create test tables
ActiveRecord::Schema.define do
  enable_extension "pg_trgm" if extension_enabled?("pg_trgm")

  create_table :todos, force: true do |t|
    t.string :title
    t.text :description
    t.integer :user_id
    t.string :status
    t.date :due_at
    t.string :priority
    t.boolean :completed, default: false
    t.jsonb :metadata, default: {}
    t.text :content
    t.tsvector :search_vector
    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.jsonb :preferences, default: {}
    t.timestamps
  end

  create_table :documents, force: true do |t|
    t.string :title
    t.text :body
    t.jsonb :tags, default: []
    t.point :coordinates
    t.timestamps
  end

  # Standard B-tree indexes
  add_index :todos, :user_id, name: "index_todos_on_user_id"
  add_index :todos, :due_at, name: "index_todos_on_due_at"
  add_index :todos, %i[user_id status], name: "index_todos_on_user_id_and_status"

  # Partial index
  add_index :todos, :due_at, where: "completed = false", name: "index_todos_on_due_at_incomplete"

  # GIN indexes for JSONB
  add_index :todos, :metadata, using: :gin, name: "index_todos_on_metadata_gin"
  add_index :users, :preferences, using: :gin, name: "index_users_on_preferences_gin"
  add_index :documents, :tags, using: :gin, name: "index_documents_on_tags_gin"

  # GIN index for full-text search
  add_index :todos, :search_vector, using: :gin, name: "index_todos_on_search_vector_gin"

  # GIN index for trigram similarity
  if extension_enabled?("pg_trgm")
    add_index :todos, :title, using: :gin, opclass: :gin_trgm_ops,
                              name: "index_todos_on_title_trgm"
  end

  # GiST index for geometric data
  add_index :documents, :coordinates, using: :gist, name: "index_documents_on_coordinates_gist"

  # Expression index
  add_index :todos, "lower(title)", name: "index_todos_on_lower_title"
  add_index :todos, "to_tsvector('english', title || ' ' || COALESCE(description, ''))",
            using: :gin,
            name: "index_todos_fulltext_gin"
end

def extension_enabled?(extension_name)
  ActiveRecord::Base.connection.extension_enabled?(extension_name)
rescue StandardError
  false
end

# Test models
class Todo < ActiveRecord::Base
  include IndexAccess::ModelExtension

  belongs_to :user, optional: true

  # Trigger for search_vector update (would normally be in migration)
  before_save :update_search_vector

  private

  def update_search_vector
    self.search_vector = self.class.connection.execute(
      "SELECT to_tsvector('english', #{self.class.connection.quote("#{title} #{description}")})"
    ).first["to_tsvector"]
  end
end

class User < ActiveRecord::Base
  include IndexAccess::ModelExtension

  has_many :todos
end

class Document < ActiveRecord::Base
  include IndexAccess::ModelExtension
end
