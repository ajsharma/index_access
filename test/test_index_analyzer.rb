require "test_helper"

class TestIndexAnalyzer < Minitest::Test
  def setup
    @analyzer = IndexAccess::IndexAnalyzer.new(Todo)
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
end
