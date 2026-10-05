# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# CI runs the suite against each supported Rails; locally you get the newest.
if (rails = ENV["RAILS_VERSION"])
  %w[actionpack actionview railties].each { |name| gem name, "~> #{rails}.0" }
end

gem "minitest"
gem "puma"
gem "rake"
gem "webmock"
