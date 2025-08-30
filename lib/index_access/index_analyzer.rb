module IndexAccess
  class IndexAnalyzer
    POSTGRES_INDEX_TYPES = %w[btree hash gin gist spgist brin].freeze
    JSONB_OPERATORS = %w[? ?& ?| @> <@ @? @@].freeze

    def initialize(model_class)
      @model_class = model_class
      @connection = model_class.connection
      validate_postgresql_connection!
    end

    def analyze_indexes
      @analyze_indexes ||= begin
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

      {
        name: rails_index.name,
        columns: columns,
        unique: rails_index.unique,
        where: rails_index.where,
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
  end
end
