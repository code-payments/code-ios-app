require "json"
require "time"

# Pure rewrite of .well-known/release-manifest.json, kept apart from the Fastfile so it can be
# exercised without App Store Connect. The app decodes the result in UpdateCheck.swift
# (`ReleaseManifest.parse`), so the shape here has to stay what that decoder reads.
module ReleaseManifest
  module_function

  # Returns the manifest with the given changes applied, and whether anything changed.
  #
  # - `testflight_build`: the newest processed TestFlight build number, or nil. Only ever raises
  #   `testflight.build`, so an older build being redistributed can't walk it back.
  # - `release_version`: set only by a release. Becomes `production.version` and resets
  #   `production.priority` to 0, so a forced-update priority from the previous release can't
  #   linger. The app takes the live store version from Apple's lookup; this records which
  #   version the priority applies to.
  # - Every key this doesn't own is left as it is.
  # - `updated` moves only when a value changed, so a no-op run produces no commit.
  def apply(manifest, testflight_build: nil, release_version: nil, now: Time.now.utc)
    result = JSON.parse(JSON.generate(manifest))
    changed = false

    build = Integer(testflight_build.to_s, exception: false)
    if build && build > result.dig("testflight", "build").to_i
      result["testflight"] = (result["testflight"] || {}).merge("build" => build)
      changed = true
    end

    version = release_version.to_s.strip
    unless version.empty?
      production = { "version" => version, "priority" => 0 }
      if result["production"] != (result["production"] || {}).merge(production)
        result["production"] = (result["production"] || {}).merge(production)
        changed = true
      end
    end

    result["updated"] = now.strftime("%Y-%m-%dT%H:%M:%SZ") if changed
    [result, changed]
  end

  # Reads `path`, applies the changes, and writes it back when something changed.
  def update_file(path, testflight_build: nil, release_version: nil, now: Time.now.utc)
    manifest = JSON.parse(File.read(path))
    result, changed = apply(manifest, testflight_build: testflight_build, release_version: release_version, now: now)
    File.write(path, JSON.pretty_generate(result) + "\n") if changed
    [result, changed]
  end
end
