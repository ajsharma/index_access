module WhereIndex
  class ScopeGenerator
    def initialize(model_class)
      @model_class = model_class
      @analyzer = IndexAnalyzer.new(model_class)
    end

    def generate_scopes
      return unless WhereIndex.configuration.include_model?(@model_class.name)

      @analyzer.analyze_indexes.each do |index|
        generate_scope_for_index(index)
      end
    end

    private

    attr_reader :model_class, :analyzer

    def generate_scope_for_index(index)
      case index[:using]&.downcase
      when "gin"
        generate_gin_scope(index)
      when "gist"
        generate_gist_scope(index)
      else
        generate_standard_scope(index)
      end
    end

    def generate_standard_scope(index)
      scope_name = build_scope_name(index)
      columns = index[:columns]
      where_clause = index[:where]

      # Generate specialized partial index scope if this is a partial index
      if where_clause.present?
        generate_partial_index_scope(index)
      elsif index[:expression]
        generate_expression_scope(scope_name, index[:expression], where_clause)
      elsif columns.size == 1
        generate_single_column_scope(scope_name, columns.first, where_clause)
      else
        generate_composite_scope(scope_name, columns, where_clause)
      end
    end

    def generate_gin_scope(index)
      if @analyzer.jsonb_indexes.include?(index)
        generate_jsonb_scope(index)
      elsif @analyzer.fulltext_indexes.include?(index)
        generate_fulltext_scope(index)
      else
        generate_standard_scope(index)
      end
    end

    def generate_gist_scope(index)
      # GiST indexes are typically for geometric data or custom types
      # For now, generate standard scopes but could be extended for spatial queries
      generate_standard_scope(index)
    end

    def generate_jsonb_scope(index)
      column = index[:columns].first
      base_name = build_scope_name(index)

      # Generate multiple scope methods for different JSONB operations
      generate_jsonb_contains_scope("#{base_name}_contains", column, index[:where])
      generate_jsonb_contained_scope("#{base_name}_contained", column, index[:where])
      generate_jsonb_has_key_scope("#{base_name}_has_key", column, index[:where])
      generate_jsonb_has_keys_scope("#{base_name}_has_keys", column, index[:where])
      generate_jsonb_path_scope("#{base_name}_path", column, index[:where])
    end

    def generate_fulltext_scope(index)
      if index[:expression]&.include?("to_tsvector")
        # Full-text search on expression
        scope_name = "#{build_scope_name(index)}_search"
        generate_fulltext_expression_scope(scope_name, index[:expression], index[:where])
      else
        # Trigram similarity search
        column = index[:columns].first
        scope_name = "#{build_scope_name(index)}_similar"
        generate_similarity_scope(scope_name, column, index[:where])
      end
    end

    def build_scope_name(index)
      prefix = WhereIndex.configuration.scope_prefix

      # For partial indexes, use the index name to create more descriptive names
      if index[:where].present? && index[:where_conditions].present?
        return build_partial_index_scope_name(index, prefix)
      end

      # Check if any column contains expressions (functions, operators, etc.)
      has_expressions = index[:columns].any? { |col| col.include?("(") || col.include?("::") }

      if has_expressions
        # For expression indexes, create a simple name based on the index name
        # Remove common prefixes and make it readable
        name_parts = index[:name].gsub(/^index_\w+_on_/, "").split("_")
        clean_name = name_parts.reject { |part| %w[gin gist btree].include?(part) }.join("_")
        "#{prefix}#{clean_name}"
      else
        columns = index[:columns].join("_")
        "#{prefix}#{columns}"
      end
    end

    def generate_single_column_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |value|
        scope = where(column => value)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_composite_scope(scope_name, columns, where_clause)
      return if @model_class.respond_to?(scope_name)

      generator = self
      @model_class.define_singleton_method(scope_name) do |**args|
        generator.send(:validate_composite_arguments!, columns, args)

        # Convert columns to symbols, handling both string and symbol cases
        required_columns = columns.map { |col| col.to_s.to_sym }
        scope = where(args.slice(*required_columns))
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_expression_scope(scope_name, expression, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |value|
        scope = where("(#{expression}) = ?", value)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_jsonb_contains_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |hash|
        scope = where("#{column} @> ?", hash.to_json)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_jsonb_contained_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |hash|
        scope = where("#{column} <@ ?", hash.to_json)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_jsonb_has_key_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |key|
        scope = where("#{column} ? ?", key)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_jsonb_has_keys_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |keys|
        # Handle array of keys properly for PostgreSQL
        keys_array = Array(keys)
        placeholders = keys_array.map { "?" }.join(",")
        scope = where("#{column} ?& array[#{placeholders}]", *keys_array)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_jsonb_path_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |path, value|
        # Handle path as an array for JSONB path operations
        path_array = path.is_a?(Array) ? path : [path]
        scope = where("#{column} #>> ? = ?", path_array, value)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_fulltext_expression_scope(scope_name, expression, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |query|
        scope = where("#{expression} @@ plainto_tsquery('english', ?)", query)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def generate_similarity_scope(scope_name, column, where_clause)
      return if @model_class.respond_to?(scope_name)

      @model_class.define_singleton_method(scope_name) do |text, threshold = 0.3|
        scope = where("#{column} % ? AND similarity(#{column}, ?) > ?", text, text, threshold)
                .order("similarity(#{column}, ?) DESC", text)
        scope = scope.where(where_clause) if where_clause
        scope
      end
    end

    def validate_composite_arguments!(columns, args)
      # Convert columns to symbols, handling both string and symbol cases
      required_columns = columns.map { |col| col.to_s.to_sym }
      missing_args = required_columns - args.keys

      return if missing_args.empty?

      raise ArgumentError, "Missing required arguments: #{missing_args.join(", ")}"
    end

    def build_partial_index_scope_name(index, _prefix)
      # Use the index name directly, cleaning it up for readability
      # Example: "idx_todos_user_pending" becomes "idx_todos_user_pending"
      clean_name = index[:name].gsub(/^(index_|idx_)/, "")
      clean_name.to_s
    end

    def generate_partial_index_scope(index)
      scope_name = build_partial_index_scope_name(index, WhereIndex.configuration.scope_prefix)
      return if @model_class.respond_to?(scope_name)

      columns = index[:columns]
      where_clause = index[:where]
      where_conditions = index[:where_conditions]

      if columns.size == 1
        generate_partial_single_column_scope(scope_name, columns.first, where_clause, where_conditions)
      else
        generate_partial_composite_scope(scope_name, columns, where_clause, where_conditions)
      end
    end

    def generate_partial_single_column_scope(scope_name, column, where_clause, _where_conditions)
      @model_class.define_singleton_method(scope_name) do |value = nil|
        # Always apply the partial index WHERE clause
        scope = where(where_clause)
        # If a value is provided, also filter by the indexed column
        scope = scope.where(column => value) if value.present?
        scope
      end
    end

    def generate_partial_composite_scope(scope_name, columns, where_clause, _where_conditions)
      generator = self
      @model_class.define_singleton_method(scope_name) do |**args|
        # Always apply the partial index WHERE clause
        scope = where(where_clause)

        # If arguments are provided, validate and apply them
        if args.present?
          generator.send(:validate_composite_arguments!, columns, args)
          required_columns = columns.map { |col| col.to_s.to_sym }
          scope = scope.where(args.slice(*required_columns))
        end

        scope
      end
    end
  end
end
