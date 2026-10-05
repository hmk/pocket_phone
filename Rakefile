# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "test" << "lib"
  task.pattern = "test/**/*_test.rb"
  task.warning = false
end

desc "Run the demo: pocket_phone plus a tiny bot that texts back, on http://localhost:4567/pocket_phone"
task :demo do
  exec "bundle exec puma demo/config.ru -p #{ENV.fetch("PORT", "4567")}"
end

task default: :test
