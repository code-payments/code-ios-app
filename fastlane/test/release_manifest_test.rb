# Run with: ruby fastlane/test/release_manifest_test.rb
require "minitest/autorun"
require "tmpdir"
require_relative "../release_manifest"

class ReleaseManifestApplyTest < Minitest::Test
  NOW = Time.utc(2026, 10, 15, 12, 30, 0)
  STAMP = "2026-10-15T12:30:00Z"

  def manifest(build: 272, version: "2026.10.2", priority: 0)
    {
      "updated" => "2026-10-14T00:00:00Z",
      "production" => { "version" => version, "priority" => priority },
      "testflight" => { "build" => build }
    }
  end

  def apply(input, **changes)
    ReleaseManifest.apply(input, now: NOW, **changes)
  end

  # testflight_build

  def test_raises_the_build_and_stamps_updated
    result, changed = apply(manifest, testflight_build: 280)

    assert changed
    assert_equal 280, result.dig("testflight", "build")
    assert_equal STAMP, result["updated"]
  end

  def test_never_lowers_the_build
    result, changed = apply(manifest, testflight_build: 270)

    refute changed
    assert_equal manifest, result
  end

  def test_same_build_is_a_no_op
    result, changed = apply(manifest, testflight_build: 272)

    refute changed
    assert_equal "2026-10-14T00:00:00Z", result["updated"]
  end

  def test_accepts_the_build_as_a_string
    result, changed = apply(manifest, testflight_build: "281")

    assert changed
    assert_equal 281, result.dig("testflight", "build")
  end

  def test_ignores_a_missing_or_non_numeric_build
    [nil, "", "abc", "1.2"].each do |build|
      result, changed = apply(manifest, testflight_build: build)

      refute changed, "build #{build.inspect}"
      assert_equal manifest, result
    end
  end

  def test_adds_testflight_when_the_manifest_has_none
    input = manifest.tap { |m| m.delete("testflight") }

    result, changed = apply(input, testflight_build: 5)

    assert changed
    assert_equal({ "build" => 5 }, result["testflight"])
  end

  def test_keeps_other_testflight_keys
    input = manifest.tap { |m| m["testflight"]["notes"] = "kept" }

    result, = apply(input, testflight_build: 300)

    assert_equal({ "build" => 300, "notes" => "kept" }, result["testflight"])
  end

  # release_version

  def test_release_records_the_version_and_resets_priority
    result, changed = apply(manifest(priority: 5), release_version: "2026.10.3")

    assert changed
    assert_equal({ "version" => "2026.10.3", "priority" => 0 }, result["production"])
    assert_equal STAMP, result["updated"]
  end

  def test_release_resets_priority_on_the_same_version
    result, changed = apply(manifest(priority: 4), release_version: "2026.10.2")

    assert changed
    assert_equal 0, result.dig("production", "priority")
  end

  def test_release_already_recorded_is_a_no_op
    result, changed = apply(manifest, release_version: "2026.10.2")

    refute changed
    assert_equal manifest, result
  end

  def test_release_strips_whitespace_and_ignores_blank
    result, = apply(manifest, release_version: " 2026.10.3\n")
    assert_equal "2026.10.3", result.dig("production", "version")

    [nil, "", "  "].each do |version|
      _, changed = apply(manifest(priority: 5), release_version: version)
      refute changed, "version #{version.inspect}"
    end
  end

  def test_release_keeps_other_production_keys
    input = manifest.tap { |m| m["production"]["notes"] = "kept" }

    result, = apply(input, release_version: "2026.10.3")

    assert_equal "kept", result.dig("production", "notes")
  end

  def test_release_leaves_the_testflight_build_alone
    result, = apply(manifest, release_version: "2026.10.3")

    assert_equal 272, result.dig("testflight", "build")
  end

  # Both together, and general guarantees

  def test_applies_build_and_release_together
    result, changed = apply(manifest(priority: 3), testflight_build: 290, release_version: "2026.10.3")

    assert changed
    assert_equal 290, result.dig("testflight", "build")
    assert_equal({ "version" => "2026.10.3", "priority" => 0 }, result["production"])
  end

  def test_keeps_keys_it_does_not_own
    input = manifest.merge("android" => { "build" => 9 })

    result, = apply(input, testflight_build: 300)

    assert_equal({ "build" => 9 }, result["android"])
  end

  def test_does_not_mutate_its_input
    input = manifest
    snapshot = Marshal.load(Marshal.dump(input))

    apply(input, testflight_build: 300, release_version: "2026.10.3")

    assert_equal snapshot, input
  end
end

class ReleaseManifestUpdateFileTest < Minitest::Test
  NOW = Time.utc(2026, 10, 15, 12, 30, 0)
  ORIGINAL = <<~JSON
    {
      "updated": "2026-10-14T00:00:00Z",
      "production": { "version": "2026.10.2", "priority": 0 },
      "testflight": { "build": 272 }
    }
  JSON

  def with_manifest(contents = ORIGINAL)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "release-manifest.json")
      File.write(path, contents)
      yield path
    end
  end

  def test_writes_pretty_json_with_a_trailing_newline_when_changed
    with_manifest do |path|
      result, changed = ReleaseManifest.update_file(path, testflight_build: 280, now: NOW)

      assert changed
      written = File.read(path)
      assert_equal JSON.pretty_generate(result) + "\n", written
      assert_equal 280, JSON.parse(written).dig("testflight", "build")
    end
  end

  def test_leaves_the_file_byte_for_byte_when_nothing_changed
    with_manifest do |path|
      _, changed = ReleaseManifest.update_file(path, testflight_build: 100, now: NOW)

      refute changed
      assert_equal ORIGINAL, File.read(path)
    end
  end

  def test_raises_when_the_file_is_missing
    Dir.mktmpdir do |dir|
      assert_raises(Errno::ENOENT) do
        ReleaseManifest.update_file(File.join(dir, "missing.json"), testflight_build: 1)
      end
    end
  end
end

# The app decodes the manifest in UpdateCheck.swift (`ReleaseManifest.parse`): production.version
# and production.priority are required, testflight.build is optional. This keeps the committed file
# readable by that decoder.
class CommittedReleaseManifestTest < Minitest::Test
  PATH = File.expand_path("../../.well-known/release-manifest.json", __dir__)

  def test_committed_manifest_has_the_shape_the_app_decodes
    manifest = JSON.parse(File.read(PATH))

    assert_kind_of String, manifest.dig("production", "version")
    assert_kind_of Integer, manifest.dig("production", "priority")
    build = manifest.dig("testflight", "build")
    assert_kind_of Integer, build unless build.nil?
  end
end
