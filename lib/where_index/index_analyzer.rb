module WhereIndex
  class IndexAnalyzer
    POSTGRES_INDEX_TYPES = %w[btree hash gin gist spgist brin].freeze
    JSONB_OPERATORS = %w[? ?& ?| @> <@ @? @@].freeze

    def initialize(model_class)
      @model_class = model_class
      @connection = model_class.connection
      validate_postgresql_connection!
    end

    def analyze_indexes
      @analyze_indexes ||= if use_schema_cache?
                             # Use schema cache when available, fallback to direct queries for missing data
                             rails_indexes = @connection.indexes(@model_class.table_name)
                             enhance_rails_indexes_from_cache_or_db(rails_indexes)
                           else
                             # Original behavior: direct PostgreSQL queries
                             pg_indexes = fetch_postgresql_indexes
                             rails_indexes = @connection.indexes(@model_class.table_name)
                             merge_index_data(rails_indexes, pg_indexes)
                           end
    end

    def composite_indexes
      analyze_indexes.select { |index| index[:columns].size > 1 }
    end

    def single_column_indexes
      analyze_indexes.select { |index| index[:columns].size == 1 }
    end

    def partial_indexes
      analyze_indexes.select { |index| index[:where].present? }
    end

    def gin_indexes
      analyze_indexes.select { |index| index[:using]&.downcase == "gin" }
    end

    def gist_indexes
      analyze_indexes.select { |index| index[:using]&.downcase == "gist" }
    end

    def expression_indexes
      analyze_indexes.select { |index| index[:expression].present? }
    end

    def jsonb_indexes
      gin_indexes.select do |index|
        index[:opclasses]&.any? { |opclass| opclass.include?("jsonb") } ||
          index[:columns].any? { |col| jsonb_column?(col) }
      end
    end

    def fulltext_indexes
      gin_indexes.select do |index|
        index[:opclasses]&.any? { |opclass| opclass.include?("gin_trgm") } ||
          index[:expression]&.include?("to_tsvector")
      end
    end

    private

    attr_reader :model_class, :connection

    def validate_postgresql_connection!
      return if connection.adapter_name.downcase == "postgresql"

      raise IndexAccess::Error, "IndexAccess requires a PostgreSQL database connection"
    end

    def use_schema_cache?
      # Check if ActiveRecord is configured to use schema cache dump
      return false unless Rails.respond_to?(:application) && Rails.application

      config = Rails.application.config
      return false unless config.respond_to?(:active_record)

      ar_config = config.active_record
      ar_config.respond_to?(:use_schema_cache_dump) && ar_config.use_schema_cache_dump == true
    rescue StandardError
      false
    end

    def enhance_rails_indexes_from_cache_or_db(rails_indexes)
      # Try to get additional PostgreSQL-specific data from cache first
      # Fall back to direct database queries only when necessary
      rails_indexes.map do |rails_index|
        cached_pg_data = get_cached_postgres_data(rails_index.name)

        if cached_pg_data&.complete?
          build_index_hash(rails_index, cached_pg_data)
        else
          # Fallback: fetch specific index data from database
          pg_data = fetch_single_postgresql_index(rails_index.name)
          build_index_hash(rails_index, pg_data)
        end
      end
    end

    def get_cached_postgres_data(_index_name)
      # ActiveRecord's schema cache doesn't include PostgreSQL-specific index data
      # like operator classes, using method, etc. Return nil to trigger fallback
      nil
    end

    def fetch_single_postgresql_index(index_name)
      query = <<~SQL
        SELECT#{" "}
          i.indexname as name,
          i.indexdef as definition,
          am.amname as using,
          idx.indisunique as unique,
          pg_get_expr(idx.indpred, idx.indrelid) as where_clause
        FROM pg_indexes i
        JOIN pg_class c ON c.relname = i.tablename
        JOIN pg_index idx ON idx.indrelid = c.oid
        JOIN pg_class ic ON ic.oid = idx.indexrelid
        JOIN pg_am am ON am.oid = ic.relam
        WHERE i.schemaname = 'public'#{" "}
          AND i.tablename = $1
          AND i.indexname = $2
          AND NOT idx.indisprimary
      SQL

      result = connection.exec_query(query, "SCHEMA", [@model_class.table_name, index_name])
      result.first
    end

    def fetch_postgresql_indexes
      query = <<~SQL
        SELECT#{" "}
          i.indexname as name,
          i.indexdef as definition,
          am.amname as using,
          idx.indisunique as unique,
          pg_get_expr(idx.indpred, idx.indrelid) as where_clause
        FROM pg_indexes i
        JOIN pg_class c ON c.relname = i.tablename
        JOIN pg_index idx ON idx.indrelid = c.oid
        JOIN pg_class ic ON ic.oid = idx.indexrelid
        JOIN pg_am am ON am.oid = ic.relam
        WHERE i.schemaname = 'public'#{" "}
          AND i.tablename = $1
          AND NOT idx.indisprimary
      SQL

      connection.exec_query(query, "SCHEMA", [@model_class.table_name])
    end

    def merge_index_data(rails_indexes, pg_indexes)
      rails_indexes.map do |rails_index|
        build_index_hash(rails_index, find_pg_data(pg_indexes, rails_index.name))
      end
    end

    def find_pg_data(pg_indexes, index_name)
      pg_indexes.find { |pg_idx| pg_idx["name"] == index_name }
    end

    def build_index_hash(rails_index, pg_data)
      columns = normalize_columns(rails_index.columns)
      where_clause = rails_index.where || pg_data&.fetch("where_clause")

      {
        name: rails_index.name,
        columns: columns,
        unique: rails_index.unique,
        where: where_clause,
        where_conditions: parse_where_conditions(where_clause),
        type: rails_index.type,
        using: pg_data&.fetch("using", "btree"),
        expression: extract_expression(columns),
        definition: pg_data&.fetch("definition"),
        opclasses: extract_opclasses_from_definition(pg_data&.fetch("definition", ""))
      }
    end

    def normalize_columns(columns)
      Array(columns).map(&:to_s)
    end

    def extract_expression(columns)
      has_expression = columns.any? { |col| col.include?("(") || col.include?("::") }
      has_expression ? columns.first : nil
    end

    def extract_opclasses_from_definition(definition)
      # Extract operator classes from the index definition
      # Example: "gin_trgm_ops", "jsonb_ops", etc.
      opclass_matches = definition.scan(/(\w+_ops)/)
      opclass_matches.flatten.uniq
    end

    def jsonb_column?(column_name)
      column = @model_class.columns.find { |c| c.name == column_name }
      column&.type == :jsonb
    end

    def parse_where_conditions(where_clause)
      return {} if where_clause.blank?

      conditions = {}
      parse_equality_conditions(where_clause, conditions)
      parse_boolean_conditions(where_clause, conditions)
      parse_null_conditions(where_clause, conditions)
      parse_not_null_conditions(where_clause, conditions)
      conditions
    end

    def parse_equality_conditions(where_clause, conditions)
      equality_matches = where_clause.scan(/\(?(\w+)\s*=\s*'([^']+)'\)?/)
      equality_matches.each do |column, value|
        conditions[column.to_sym] = value
      end
    end

    def parse_boolean_conditions(where_clause, conditions)
      boolean_matches = where_clause.scan(/\(?(\w+)\s*=\s*(true|false)\)?/)
      boolean_matches.each do |column, value|
        conditions[column.to_sym] = value == "true"
      end
    end

    def parse_null_conditions(where_clause, conditions)
      null_matches = where_clause.scan(/\(?(\w+)\s+IS\s+NULL\)?/i)
      null_matches.each do |column_match|
        column = column_match.is_a?(Array) ? column_match.first : column_match
        conditions[column.to_sym] = nil
      end
    end

    def parse_not_null_conditions(where_clause, conditions)
      not_null_matches = where_clause.scan(/\(?(\w+)\s+IS\s+NOT\s+NULL\)?/i)
      not_null_matches.each do |column_match|
        column = column_match.is_a?(Array) ? column_match.first : column_match
        conditions[:"#{column}_not_null"] = true
      end
    end
  end
end
