# frozen_string_literal: true

require_relative "lib/pocket_phone/version"

Gem::Specification.new do |spec|
  spec.name = "pocket_phone"
  spec.version = PocketPhone::VERSION
  spec.authors = ["hmk"]
  spec.email = ["hmk@users.noreply.github.com"]

  spec.summary = "A fake Sendblue for development: text your app from a phone in the browser."
  spec.description = "Like letter_opener, but for iMessage and SMS, and in both directions. " \
                     "pocket_phone is a mountable Rails engine that answers the Sendblue API, shows what your " \
                     "app sent in an iMessage-style inbox, and lets you text back through signed webhooks."
  spec.homepage = "https://github.com/hmk/pocket_phone"
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["app/**/*", "config/**/*", "lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "actionview", ">= 7.1"
  spec.add_dependency "nokogiri", ">= 1.13"
  spec.add_dependency "railties", ">= 7.1"
end
