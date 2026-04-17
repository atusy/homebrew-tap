#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Automated Homebrew formula updater for the kakehashi tap.
#
# Entry points:
#   ruby scripts/update_formulas.rb                 # run the updater
#   ruby scripts/update_formulas.rb --self-test     # pure-helper assertions
#   ruby scripts/update_formulas.rb --regenerate    # rebuild .rb files from versions.json
#   GH_TOKEN=... ruby scripts/update_formulas.rb --probe v0.5.0
#
# Environment:
#   GH_TOKEN       - required for the default run and --probe
#   UPSTREAM_REPO  - defaults to "atusy/kakehashi"
#   DRY_RUN        - "true" to skip file writes
#   GITHUB_OUTPUT  - set by Actions for output variables

require "json"
require "open3"
require "rubygems"

# Fetches upstream releases and updates Formula/versions.json accordingly,
# then regenerates the static .rb formula files from the JSON data.
module FormulaUpdater
  UPSTREAM_REPO = ENV.fetch("UPSTREAM_REPO", "atusy/kakehashi").freeze
  DRY_RUN       = ENV["DRY_RUN"] == "true"
  VERSIONS_PATH = "Formula/versions.json"

  TARGETS = %w[
    aarch64-apple-darwin
    x86_64-apple-darwin
    aarch64-unknown-linux-gnu
    x86_64-unknown-linux-gnu
  ].freeze

  TARGET_TO_JSON = {
    "aarch64-apple-darwin"      => %w[macos arm],
    "x86_64-apple-darwin"       => %w[macos intel],
    "aarch64-unknown-linux-gnu" => %w[linux arm],
    "x86_64-unknown-linux-gnu"  => %w[linux intel],
  }.freeze

  module_function

  # --- pure helpers ----------------------------------------------------------

  def parse_semver(tag)
    return unless tag =~ /\Av(\d+\.\d+\.\d+)\z/

    Gem::Version.new(Regexp.last_match(1))
  end

  def class_name_for(major, minor)
    "KakehashiAT#{major}#{minor}"
  end

  # --- upstream fetch --------------------------------------------------------

  def gh_api(path, paginate: false)
    cmd = ["gh", "api", "-H", "Accept: application/vnd.github+json", path]
    cmd.push("--paginate", "--slurp") if paginate
    out, err, status = Open3.capture3(*cmd)
    raise "gh api #{path} failed: #{err}" unless status.success?

    data = JSON.parse(out)
    paginate ? data.flatten : data
  end

  def fetch_releases
    gh_api("/repos/#{UPSTREAM_REPO}/releases", paginate: true)
  end

  @release_info_cache = {}

  def release_info(tag)
    return @release_info_cache[tag] if @release_info_cache.key?(tag)

    rel = gh_api("/repos/#{UPSTREAM_REPO}/releases/tags/#{tag}")
    assets = rel.fetch("assets", [])
    out = {}
    TARGETS.each do |target|
      asset = assets.find { |a| a["name"] == "kakehashi-#{tag}-#{target}.tar.gz" }
      if !asset || !(asset["digest"].is_a?(String) && asset["digest"].start_with?("sha256:"))
        @release_info_cache[tag] = nil
        return nil
      end
      out[target] = {
        url:    asset.fetch("browser_download_url"),
        sha256: asset["digest"].delete_prefix("sha256:"),
      }
    end
    @release_info_cache[tag] = out
  end

  # --- JSON building ---------------------------------------------------------

  def release_to_json_entry(version, assets)
    entry = { "version" => version.to_s }
    TARGET_TO_JSON.each do |target, (os, arch)|
      entry[os] ||= {}
      entry[os][arch] = {
        "url"    => assets[target][:url],
        "sha256" => assets[target][:sha256],
      }
    end
    entry
  end

  def build_versions_json(current_json, latest_per_mm, overall_latest_entry, new_main_mm, report)
    result = {}

    main_assets = release_info(overall_latest_entry[:tag])
    if main_assets
      result[""] = release_to_json_entry(overall_latest_entry[:version], main_assets)
    else
      report[:skipped] << { tag: overall_latest_entry[:tag], reason: "missing assets (main)" }
      result[""] = current_json[""]
    end

    latest_per_mm.each do |(major, minor), entry|
      key = "#{major}.#{minor}"
      next if !current_json.key?(key) && new_main_mm != [major, minor]

      assets = release_info(entry[:tag])
      if assets
        result[key] = release_to_json_entry(entry[:version], assets)
      else
        report[:skipped] << { tag: entry[:tag], reason: "missing assets" }
        result[key] = current_json[key] if current_json.key?(key)
      end
    end

    result
  end

  # --- static formula generation ---------------------------------------------

  # Extract the `test do ... end` block from an existing formula source.
  # Returns the block as a string (with leading indentation) or nil.
  def extract_test_block(src)
    src[/^  test do\n.*?^  end$/m]
  end

  DEFAULT_TEST_BLOCK = <<~RUBY.chomp.freeze
    test do
      assert_match(/\\Akakehashi \#{Regexp.escape(version.to_s)}\\b/,
                   shell_output("\#{bin}/kakehashi --version"))

      require "json"
      schema = shell_output("\#{bin}/kakehashi config schema")
      parsed = JSON.parse(schema)
      assert_kind_of Hash, parsed, "expected JSON object at root of config schema"
      refute_empty parsed, "config schema should not be empty"
    end
  RUBY

  # Generate a complete formula .rb source from JSON data.
  def generate_formula_source(klass, data, test_block, livecheck: false, keg_only: false)
    lines = []
    lines << "class #{klass} < Formula"
    lines << '  desc "Language server bridging the gap between languages, editors, and tooling"'
    lines << '  homepage "https://github.com/atusy/kakehashi"'
    lines << '  license "MIT"'

    if livecheck
      lines << ""
      lines << "  livecheck do"
      lines << "    url :stable"
      lines << "    strategy :github_latest"
      lines << "  end"
    end

    lines << "" << "  keg_only :versioned_formula" if keg_only

    lines << ""
    lines << "  on_macos do"
    lines << "    on_arm do"
    lines << "      url \"#{data.dig("macos", "arm", "url")}\""
    lines << "      sha256 \"#{data.dig("macos", "arm", "sha256")}\""
    lines << "    end"
    lines << "    on_intel do"
    lines << "      url \"#{data.dig("macos", "intel", "url")}\""
    lines << "      sha256 \"#{data.dig("macos", "intel", "sha256")}\""
    lines << "    end"
    lines << "  end"

    lines << ""
    lines << "  on_linux do"
    lines << "    on_arm do"
    lines << "      url \"#{data.dig("linux", "arm", "url")}\""
    lines << "      sha256 \"#{data.dig("linux", "arm", "sha256")}\""
    lines << "    end"
    lines << "    on_intel do"
    lines << "      url \"#{data.dig("linux", "intel", "url")}\""
    lines << "      sha256 \"#{data.dig("linux", "intel", "sha256")}\""
    lines << "    end"
    lines << "  end"

    lines << ""
    lines << "  def install"
    lines << '    bin.install "kakehashi"'
    lines << "  end"

    lines << ""
    # test_block already includes `  test do` and `  end` with proper indentation
    lines << test_block

    lines << "end"
    "#{lines.join("\n")}\n"
  end
  # rubocop:enable Metrics/MethodLength

  # Regenerate a single formula .rb file from versions.json data.
  def regenerate_formula!(path, key, data, livecheck: false, keg_only: false)
    # Preserve existing test block if the file already exists.
    test_block = (extract_test_block(File.read(path)) if File.exist?(path))
    test_block ||= latest_versioned_test_block || "  #{DEFAULT_TEST_BLOCK}"

    klass = if key == ""
      "Kakehashi"
    else
      parts = key.split(".")
      class_name_for(parts[0].to_i, parts[1].to_i)
    end

    src = generate_formula_source(klass, data, test_block, livecheck: livecheck, keg_only: keg_only)
    File.write(path, src) unless DRY_RUN
  end

  # Find the test block from the newest existing versioned formula.
  def latest_versioned_test_block
    template = Dir["Formula/kakehashi@*.rb"]
               .max_by { |p| Gem::Version.new(File.basename(p, ".rb").sub(/^kakehashi@/, "")) }
    return unless template

    extract_test_block(File.read(template))
  end

  # Regenerate all formula .rb files from the current versions.json.
  def regenerate_all!
    json = JSON.parse(File.read(VERSIONS_PATH))
    json.each do |key, data|
      path = (key == "") ? "Formula/kakehashi.rb" : "Formula/kakehashi@#{key}.rb"
      regenerate_formula!(path, key, data, livecheck: key == "", keg_only: key != "")
    end
  end

  # --- main orchestration ----------------------------------------------------

  # Orchestration is clearer as one sequential flow.
  # rubocop:disable Metrics/MethodLength
  def run_updater
    parsed = fetch_releases.filter_map do |r|
      next nil if r["draft"] || r["prerelease"]

      v = parse_semver(r["tag_name"])
      v ? { version: v, tag: r["tag_name"] } : nil
    end

    report = { changed: false, main: nil, updated: [], created: [], skipped: [] }

    if parsed.empty?
      write_report(report)
      return
    end

    latest_per_mm = parsed
                    .group_by { |e| [e[:version].segments[0], e[:version].segments[1]] }
                    .transform_values { |v| v.max_by { |e| e[:version] } }
    overall_latest = parsed.max_by { |e| e[:version] }

    current_json = JSON.parse(File.read(VERSIONS_PATH))
    current_main_ver = Gem::Version.new(current_json.dig("", "version"))
    new_main_ver = [overall_latest[:version], current_main_ver].max
    new_main_mm = [new_main_ver.segments[0], new_main_ver.segments[1]]

    target_json = build_versions_json(current_json, latest_per_mm, overall_latest, new_main_mm, report)

    if target_json != current_json
      File.write(VERSIONS_PATH, "#{JSON.pretty_generate(target_json)}\n") unless DRY_RUN
      report[:changed] = true

      old_main = current_json.dig("", "version")
      new_main = target_json.dig("", "version")
      report[:main] = { from: old_main, to: new_main } if old_main != new_main

      target_json.each do |key, entry|
        next if key == ""

        old_entry = current_json[key]
        if old_entry.nil?
          report[:created] << { key: key, version: entry["version"] }
        elsif old_entry["version"] != entry["version"]
          report[:updated] << { key: key, from: old_entry["version"], to: entry["version"] }
        end
      end

      # Regenerate .rb files for all changed keys.
      regenerate_all! unless DRY_RUN
    end

    write_report(report)
  end
  # rubocop:enable Metrics/MethodLength

  # Report format kept in one place for readability.
  # rubocop:disable Metrics/MethodLength
  def write_report(report)
    md_path = File.expand_path("update_report.md")
    File.open(md_path, "w") do |io|
      io.puts "## Formula auto-update report"
      io.puts
      io.puts(report[:main] ? "- Main: `#{report[:main][:from]}` -> `#{report[:main][:to]}`" : "- Main: no change")
      report[:updated].each { |u| io.puts "- Updated `@#{u[:key]}`: `#{u[:from]}` -> `#{u[:to]}`" }
      report[:created].each { |c| io.puts "- Created `@#{c[:key]}` at `#{c[:version]}`" }
      unless report[:skipped].empty?
        io.puts
        io.puts "### Skipped"
        report[:skipped].each { |s| io.puts "- `#{s[:tag]}`: #{s[:reason]}" }
      end
      io.puts("\n_DRY_RUN: no files were modified._") if DRY_RUN
    end

    title = report[:changed] ? "chore: update kakehashi formulas" : "chore: no-op"
    if (gh_out = ENV.fetch("GITHUB_OUTPUT", nil))
      File.open(gh_out, "a") do |io|
        io.puts "changed=#{report[:changed]}"
        io.puts "pr_title=#{title}"
        io.puts "report_markdown_path=#{md_path}"
      end
    end

    puts File.read(md_path)
  end
  # rubocop:enable Metrics/MethodLength

  # --- self-test -------------------------------------------------------------

  # Inline test suite kept as one method for simplicity.
  # rubocop:disable Metrics/MethodLength
  def self_test
    failures = []

    cases = {
      "v0.5.0" => Gem::Version.new("0.5.0"), "v1.2.3" => Gem::Version.new("1.2.3"),
      "v10.20.30" => Gem::Version.new("10.20.30"),
      "0.5.0" => nil, "v0.5" => nil, "v0.5.0-rc.1" => nil, "v0.5.0+b1" => nil,
      "invalid" => nil, "" => nil
    }
    cases.each do |tag, expected|
      got = parse_semver(tag)
      failures << "parse_semver(#{tag.inspect}) => #{got.inspect}, expected #{expected.inspect}" if got != expected
    end

    class_cases = {
      [0, 1] => "KakehashiAT01", [0, 4] => "KakehashiAT04",
      [0, 5] => "KakehashiAT05", [1, 0] => "KakehashiAT10",
      [0, 10] => "KakehashiAT010"
    }
    class_cases.each do |(major, minor), expected|
      got = class_name_for(major, minor)
      if got != expected
        failures << "class_name_for(#{major}, #{minor}) => #{got.inspect}, expected #{expected.inspect}"
      end
    end

    # Test extract_test_block on a fixture.
    fixture = "class Foo < Formula\n  def install\n  end\n\n  test do\n    assert true\n  end\nend\n"
    extracted = extract_test_block(fixture)
    expected_block = "  test do\n    assert true\n  end"
    failures << "extract_test_block: #{extracted.inspect}" if extracted != expected_block

    # Test generate_formula_source round-trip.
    data = {
      "macos" => { "arm" => { "url" => "u1", "sha256" => "s1" }, "intel" => { "url" => "u2", "sha256" => "s2" } },
      "linux" => { "arm" => { "url" => "u3", "sha256" => "s3" }, "intel" => { "url" => "u4", "sha256" => "s4" } },
    }
    src = generate_formula_source("Kakehashi", data, "  test do\n  end", livecheck: true)
    failures << "generate: missing class" unless src.include?("class Kakehashi < Formula")
    failures << "generate: missing livecheck" unless src.include?("strategy :github_latest")
    failures << "generate: missing url" unless src.include?('url "u1"')
    failures << "generate: has keg_only" if src.include?("keg_only")

    total = cases.size + class_cases.size + 5
    if failures.empty?
      puts "ok (#{total} assertions)"
      exit 0
    else
      warn "self-test failed:"
      failures.each { |f| warn "  - #{f}" }
      exit 1
    end
  end

  def probe(tag)
    info = release_info(tag)
    if info.nil?
      warn "release #{tag}: missing one or more expected assets or digests"
      exit 1
    end
    info.each do |target, data|
      puts target
      puts "  url    #{data[:url]}"
      puts "  sha256 #{data[:sha256]}"
    end
  end
end

# --- entrypoint --------------------------------------------------------------

if $PROGRAM_NAME == __FILE__
  case ARGV.first
  when "--self-test"
    FormulaUpdater.self_test
  when "--probe"
    tag = ARGV[1]
    unless tag
      warn "usage: #{$PROGRAM_NAME} --probe <tag>"
      exit 2
    end
    FormulaUpdater.probe(tag)
  when "--regenerate"
    FormulaUpdater.regenerate_all!
    puts "regenerated formula files from #{FormulaUpdater::VERSIONS_PATH}"
  when nil
    FormulaUpdater.run_updater
  else
    warn "usage: #{$PROGRAM_NAME} [--self-test | --probe <tag> | --regenerate]"
    exit 2
  end
end
