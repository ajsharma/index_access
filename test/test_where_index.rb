require "test_helper"

class TestWhereIndex < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::WhereIndex::VERSION
  end

  def test_configuration
    WhereIndex.configure do |config|
      config.scope_prefix = "via_"
      config.auto_generate = false
    end

    assert_equal "via_", WhereIndex.configuration.scope_prefix
    assert_equal false, WhereIndex.configuration.auto_generate

    WhereIndex.reset_configuration!
  end

  def test_include_model_with_empty_included_models
    config = WhereIndex::Configuration.new
    assert config.include_model?("Todo")
    assert config.include_model?("User")
  end

  def test_include_model_with_included_models
    config = WhereIndex::Configuration.new
    config.included_models = ["Todo"]

    assert config.include_model?("Todo")
    refute config.include_model?("User")
  end

  def test_include_model_with_excluded_models
    config = WhereIndex::Configuration.new
    config.excluded_models = ["User"]

    assert config.include_model?("Todo")
    refute config.include_model?("User")
  end
end
