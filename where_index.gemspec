require_relative "lib/where_index/version"

Gem::Specification.new do |spec|
  spec.name = "where_index"
  spec.version = WhereIndex::VERSION
  spec.authors = ["Ajay Sharma"]
  spec.email = ["aj@ajsharma.com"]

  spec.summary = "PostgreSQL-focused ActiveRecord scopes that automatically utilize database indexes"
  spec.description = <<~DESCRIPTION
    A Ruby gem that leverages PostgreSQL's advanced indexing features to automatically
    generate matching ActiveRecord scopes, including support for GIN, GiST, partial,
    and expression indexes.
  DESCRIPTION
  spec.homepage = "https://github.com/ajsharma/where_index"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ajsharma/where_index"
  spec.metadata["changelog_uri"] = "https://github.com/ajsharma/where_index/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "pg", ">= 1.1"
end
