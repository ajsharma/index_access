require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

begin
  require "appraisal"
  require "appraisal/task"
  Appraisal::Task.new
rescue LoadError
  # Appraisal not available
end

task default: %i[test rubocop]
