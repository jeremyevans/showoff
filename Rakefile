desc "Build HTML documentation"
task :doc do
  system("rdoc --main README.rdoc README.rdoc documentation/*.rdoc")
end

require 'rake/testtask'

desc "Run tests"
Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end

desc "Build gem"
task :package do |p|
  sh %{#{FileUtils::RUBY} -S gem build showoff.gemspec}
end
