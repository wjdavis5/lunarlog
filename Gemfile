# frozen_string_literal: true

# Pins the fastlane version that .github/workflows/ios-release.yml's
# "Submit for App Store review" step runs as `bundle exec fastlane ios
# submit` (issue #208), so a submission no longer depends on whatever
# fastlane the self-hosted runner happens to have installed. To bump:
# change the version here, run `bundle lock --add-platform ruby` to
# regenerate Gemfile.lock, and commit both in the same change.

source "https://rubygems.org"

gem "fastlane", "2.237.0"
