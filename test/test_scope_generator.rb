require "test_helper"

class TestScopeGenerator < Minitest::Test
  def setup
    @generator = IndexAccess::ScopeGenerator.new(Todo)
    @generator.generate_scopes
  end

  def teardown
    IndexAccess.reset_configuration!
  end

  def test_generates_single_column_scopes
    assert Todo.respond_to?(:index_user_id)
    assert Todo.respond_to?(:index_due_at)
  end

  def test_generates_composite_scopes
    assert Todo.respond_to?(:index_user_id_status)
  end

  def test_single_column_scope_functionality
    user = User.create!(name: "Test User", email: "test@example.com")
    todo = Todo.create!(title: "Test Todo", user_id: user.id, status: "pending")

    result = Todo.index_user_id(user.id)
    assert_includes result, todo
  end

  def test_composite_scope_functionality
    user = User.create!(name: "Test User", email: "test@example.com")
    todo = Todo.create!(title: "Test Todo", user_id: user.id, status: "pending")

    result = Todo.index_user_id_status(user_id: user.id, status: "pending")
    assert_includes result, todo
  end

  def test_composite_scope_raises_error_for_missing_arguments
    assert_raises(ArgumentError) do
      Todo.index_user_id_status(user_id: 1)
    end
  end

  def test_respects_included_models_configuration
    IndexAccess.configure do |config|
      config.included_models = ["User"]
    end

    generator = IndexAccess::ScopeGenerator.new(Todo)
    generator.generate_scopes

    # Should not generate scopes for Todo since it's not in included_models
    refute Todo.respond_to?(:index_email)
  end

  def test_custom_scope_prefix
    IndexAccess.configure do |config|
      config.scope_prefix = "via_"
    end

    generator = IndexAccess::ScopeGenerator.new(User)
    generator.generate_scopes

    assert User.respond_to?(:via_email) if User.connection.indexes("users").any? { |idx| idx.columns.include?("email") }
  end
end
