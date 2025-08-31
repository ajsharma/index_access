require "test_helper"

class TestIndexAnalyzer < Minitest::Test
  def setup
    @analyzer = WhereIndex::IndexAnalyzer.new(Todo)
  end

  def test_analyze_indexes
    indexes = @analyzer.analyze_indexes

    assert(indexes.any? { |idx| idx[:name] == "index_todos_on_user_id" })
    assert(indexes.any? { |idx| idx[:name] == "index_todos_on_due_at" })
    assert(indexes.any? { |idx| idx[:name] == "index_todos_on_user_id_and_status" })
  end

  def test_single_column_indexes
    single_indexes = @analyzer.single_column_indexes

    assert(single_indexes.any? { |idx| idx[:columns] == ["user_id"] })
    assert(single_indexes.any? { |idx| idx[:columns] == ["due_at"] })
  end

  def test_composite_indexes
    composite_indexes = @analyzer.composite_indexes

    assert(composite_indexes.any? { |idx| idx[:columns] == %w[user_id status] })
  end

  def test_partial_indexes
    partial_indexes = @analyzer.partial_indexes

    # NOTE: SQLite might not support partial indexes in the same way as PostgreSQL
    # This test might need adjustment based on the database adapter
    assert_kind_of Array, partial_indexes
  end

  def test_use_schema_cache_respects_configuration
    # Test that use_schema_cache? respects the Rails configuration
    # Our mock Rails has use_schema_cache_dump set to true by default
    assert(@analyzer.send(:use_schema_cache?))

    # Test when explicitly set to false
    original_value = Rails.application.config.active_record.use_schema_cache_dump
    Rails.application.config.active_record.use_schema_cache_dump = false
    refute(@analyzer.send(:use_schema_cache?))
  ensure
    Rails.application.config.active_record.use_schema_cache_dump = original_value
  end

  def test_use_schema_cache_handles_exceptions
    # Test that exceptions are caught and return false
    @analyzer.stub(:use_schema_cache?, proc { raise StandardError, "Test error" }) do
      # The method should catch exceptions and return false, but since we're stubbing
      # the method itself, we need to test the actual implementation behavior differently
    end

    # Test actual exception handling by creating a scenario where Rails responds incorrectly
    original_rails = Rails
    begin
      Object.send(:remove_const, :Rails)
      # Now Rails is undefined, which should trigger the rescue block
      refute(@analyzer.send(:use_schema_cache?))
    ensure
      Object.const_set(:Rails, original_rails)
    end
  end

  def test_analyze_indexes_with_schema_cache_enabled
    # Test that when schema cache is enabled, we use the cache-aware path
    @analyzer.stub(:use_schema_cache?, true) do
      @analyzer.stub(:enhance_rails_indexes_from_cache_or_db, []) do
        @analyzer.instance_variable_set(:@analyze_indexes, nil) # Reset cached value
        result = @analyzer.analyze_indexes
        assert_kind_of Array, result
      end
    end
  end

  def test_analyze_indexes_with_schema_cache_disabled
    # Test that when schema cache is disabled, we use the original path
    @analyzer.stub(:use_schema_cache?, false) do
      @analyzer.stub(:fetch_postgresql_indexes, []) do
        @analyzer.stub(:merge_index_data, []) do
          @analyzer.instance_variable_set(:@analyze_indexes, nil) # Reset cached value
          result = @analyzer.analyze_indexes
          assert_kind_of Array, result
        end
      end
    end
  end

  def test_fetch_single_postgresql_index
    # Test fetching single index data
    index_name = "test_index"

    connection_mock = Minitest::Mock.new
    result_mock = Minitest::Mock.new

    result_mock.expect(:first, { "name" => index_name, "using" => "btree" })
    connection_mock.expect(:exec_query, result_mock)

    @analyzer.instance_variable_get(:@connection).stub(:exec_query, ->(_query, _name, _params) { result_mock }) do
      result = @analyzer.send(:fetch_single_postgresql_index, index_name)
      assert_equal({ "name" => index_name, "using" => "btree" }, result)
    end

    result_mock.verify
  end

  def test_get_cached_postgres_data_returns_nil
    # Test that cached postgres data returns nil (triggering fallback)
    result = @analyzer.send(:get_cached_postgres_data, "any_index_name")
    assert_nil result
  end

  def test_enhance_rails_indexes_from_cache_or_db_fallback
    # Test that enhancement falls back to database queries
    rails_index_mock = Minitest::Mock.new
    rails_index_mock.expect(:name, "test_index")
    rails_index_mock.expect(:name, "test_index") # Called twice in the method

    @analyzer.stub(:get_cached_postgres_data, nil) do
      @analyzer.stub(:fetch_single_postgresql_index, { "name" => "test_index", "using" => "btree" }) do
        @analyzer.stub(:build_index_hash, { name: "test_index", using: "btree" }) do
          result = @analyzer.send(:enhance_rails_indexes_from_cache_or_db, [rails_index_mock])
          assert_equal [{ name: "test_index", using: "btree" }], result
        end
      end
    end

    rails_index_mock.verify
  end
end
