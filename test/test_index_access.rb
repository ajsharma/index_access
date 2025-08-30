require "test_helper"

class TestIndexAccess < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::IndexAccess::VERSION
  end

  def test_configuration
    IndexAccess.configure do |config|
      config.scope_prefix = "via_"
      config.auto_generate = false
    end

    assert_equal "via_", IndexAccess.configuration.scope_prefix
    assert_equal false, IndexAccess.configuration.auto_generate

    IndexAccess.reset_configuration!
  end

  def test_include_model_with_empty_included_models
    config = IndexAccess::Configuration.new
    assert config.include_model?("Todo")
    assert config.include_model?("User")
  end

  def test_include_model_with_included_models
    config = IndexAccess::Configuration.new
    config.included_models = ["Todo"]

    assert config.include_model?("Todo")
    refute config.include_model?("User")
  end

  def test_include_model_with_excluded_models
    config = IndexAccess::Configuration.new
    config.excluded_models = ["User"]

    assert config.include_model?("Todo")
    refute config.include_model?("User")
  end
end
