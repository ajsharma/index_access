require "test_helper"

class TestScopeGenerator < Minitest::Test
  def setup
    @generator = WhereIndex::ScopeGenerator.new(Todo)
    @generator.generate_scopes
  end

  def teardown
    WhereIndex.reset_configuration!
  end

  def test_generates_single_column_scopes
    assert Todo.respond_to?(:where_index_user_id)
    assert Todo.respond_to?(:where_index_due_at)
  end

  def test_generates_composite_scopes
    assert Todo.respond_to?(:where_index_user_id_status)
  end

  def test_single_column_scope_functionality
    user = User.create!(name: "Test User", email: "test@example.com")
    todo = Todo.create!(title: "Test Todo", user_id: user.id, status: "pending")

    result = Todo.where_index_user_id(user.id)
    assert_includes result, todo
  end

  def test_composite_scope_functionality
    user = User.create!(name: "Test User", email: "test@example.com")
    todo = Todo.create!(title: "Test Todo", user_id: user.id, status: "pending")

    result = Todo.where_index_user_id_status(user_id: user.id, status: "pending")
    assert_includes result, todo
  end

  def test_composite_scope_raises_error_for_missing_arguments
    assert_raises(ArgumentError) do
      Todo.where_index_user_id_status(user_id: 1)
    end
  end

  def test_respects_included_models_configuration
    WhereIndex.configure do |config|
      config.included_models = ["User"]
    end

    generator = WhereIndex::ScopeGenerator.new(Todo)
    generator.generate_scopes

    # Should not generate scopes for Todo since it's not in included_models
    refute Todo.respond_to?(:where_index_email)
  end

  def test_custom_scope_prefix
    WhereIndex.configure do |config|
      config.scope_prefix = "via_"
    end

    generator = WhereIndex::ScopeGenerator.new(User)
    generator.generate_scopes

    assert User.respond_to?(:via_email) if User.connection.indexes("users").any? { |idx| idx.columns.include?("email") }
  end

  def test_generates_partial_index_scopes
    assert Todo.respond_to?(:todos_on_due_at_incomplete)
    assert Todo.respond_to?(:todos_user_pending)
  end

  def test_partial_index_scope_functionality
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create completed and incomplete todos
    completed_todo = Todo.create!(title: "Completed Todo", user_id: user.id, status: "done", due_at: Date.today,
                                  completed: true)
    incomplete_todo = Todo.create!(title: "Incomplete Todo", user_id: user.id, status: "pending", due_at: Date.today,
                                   completed: false)

    # The partial index scope should automatically apply WHERE completed = false
    result = Todo.todos_on_due_at_incomplete(Date.today)

    assert_includes result, incomplete_todo
    refute_includes result, completed_todo
  end

  def test_partial_index_scope_without_arguments
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create completed and incomplete todos with different due dates
    completed_todo = Todo.create!(title: "Completed Todo", user_id: user.id, status: "done", due_at: Date.today,
                                  completed: true)
    incomplete_todo1 = Todo.create!(title: "Incomplete Todo 1", user_id: user.id, status: "pending",
                                    due_at: Date.today, completed: false)
    incomplete_todo2 = Todo.create!(title: "Incomplete Todo 2", user_id: user.id, status: "pending",
                                    due_at: Date.tomorrow, completed: false)

    # Call partial index scope without arguments to get all records matching the WHERE clause
    result = Todo.todos_on_due_at_incomplete

    assert_includes result, incomplete_todo1
    assert_includes result, incomplete_todo2
    refute_includes result, completed_todo
  end

  def test_partial_index_scope_with_nil_value
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create incomplete todo with nil due_at
    incomplete_todo = Todo.create!(title: "Incomplete Todo", user_id: user.id, status: "pending", due_at: nil,
                                   completed: false)

    # The partial index scope should still apply the WHERE clause when value is nil
    result = Todo.todos_on_due_at_incomplete(nil)

    assert_includes result, incomplete_todo
  end

  def test_user_pending_partial_index_scope
    user = User.create!(name: "Test User", email: "test@example.com")
    other_user = User.create!(name: "Other User", email: "other@example.com")

    # Create todos with different statuses
    pending_todo = Todo.create!(title: "Pending Todo", user_id: user.id, status: "pending")
    done_todo = Todo.create!(title: "Done Todo", user_id: user.id, status: "done")
    other_pending = Todo.create!(title: "Other Pending", user_id: other_user.id, status: "pending")

    # Test the partial index scope automatically applies WHERE status = 'pending'
    result = Todo.todos_user_pending(user.id)

    assert_includes result, pending_todo
    refute_includes result, done_todo
    refute_includes result, other_pending
  end

  def test_user_pending_partial_index_scope_without_arguments
    user = User.create!(name: "Test User", email: "test@example.com")

    # Create todos with different statuses
    pending_todo1 = Todo.create!(title: "Pending Todo 1", user_id: user.id, status: "pending")
    pending_todo2 = Todo.create!(title: "Pending Todo 2", user_id: 999, status: "pending")
    done_todo = Todo.create!(title: "Done Todo", user_id: user.id, status: "done")

    # Call without arguments to get all pending todos regardless of user_id
    result = Todo.todos_user_pending

    assert_includes result, pending_todo1
    assert_includes result, pending_todo2
    refute_includes result, done_todo
  end
end
