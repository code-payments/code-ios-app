require "json"
require "time"

# Pure rewrite of .well-known/release-manifest.json, kept apart from the Fastfile so it can be
# exercised without App Store Connect. The app decodes the result in UpdateCheck.swift
# (`ReleaseManifest.parse`), so the shape here has to stay what that decoder reads.
module ReleaseManifest
  module_function

  # Returns the manifest with App Store Connect's answers applied, and whether anything changed.
  #
  # - `live_version`: the version live on the App Store, or nil when there is none. Replaces
  #   `production.version`; a nil keeps the existing one rather than writing null.
  # - `testflight_build`: the newest processed TestFlight build number, or nil. Only ever raises
  #   `testflight.build`, so an older build being redistributed can't walk it back.
  # - `production.priority` and every key this doesn't own are left as they are: priority is set
  #   by hand to force an update.
  # - `updated` moves only when a value changed, so a no-op run produces no commit.
  def apply(manifest, live_version:, testflight_build:, now: Time.now.utc)
    result = JSON.parse(JSON.generate(manifest))
    changed = false

    version = live_version.to_s.strip
    if !version.empty? && result.dig("production", "version") != version
      result["production"] = (result["production"] || {}).merge("version" => version)
      changed = true
    end

    build = Integer(testflight_build.to_s, exception: false)
    if build && build > result.dig("testflight", "build").to_i
      result["testflight"] = (result["testflight"] || {}).merge("build" => build)
      changed = true
    end

    result["updated"] = now.strftime("%Y-%m-%dT%H:%M:%SZ") if changed
    [result, changed]
  end

  # Reads `path`, applies the answers, and writes it back when something changed.
  def update_file(path, live_version:, testflight_build:, now: Time.now.utc)
    manifest = JSON.parse(File.read(path))
    result, changed = apply(manifest, live_version: live_version, testflight_build: testflight_build, now: now)
    File.write(path, JSON.pretty_generate(result) + "\n") if changed
    [result, changed]
  end
end
