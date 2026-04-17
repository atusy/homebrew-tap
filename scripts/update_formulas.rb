#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Automated Homebrew formula updater for the kakehashi tap.
#
# Entry points:
#   ruby scripts/update_formulas.rb                 # run the updater
#   ruby scripts/update_formulas.rb --self-test     # pure-helper assertions
#   GH_TOKEN=... ruby scripts/update_formulas.rb --probe v0.5.0
#
# Environment:
#   GH_TOKEN       - required for the default run and --probe (gh auth)
#   UPSTREAM_REPO  - e.g. "atusy/kakehashi"; defaults to that value
#   DRY_RUN        - "true" to compute the plan without writing files
#   GITHUB_OUTPUT  - set by Actions; receives `changed`, `pr_title`, and
#                    `report_markdown_path`
#
# Algorithm:
#   1. Fetch every published release from UPSTREAM_REPO.
#   2. The main formula ("" key) targets the overall latest release.
#   3. Each existing versioned key in versions.json converges to the latest
#      patch within its (M, m) group.
#   4. New keys are only added when (M, m) matches the main formula's new
#      (M, m) - preventing historic minors from materialising retroactively.
#   5. If a new key needs a .rb formula file, one is created from the latest
#      existing versioned formula as template.

require "json"
require "open3"
require "rubygems"

# Fetches upstream releases and updates Formula/versions.json accordingly.
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

  # --- pure helpers ----------------------------------------------------------

  module_function

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
      expected = "kakehashi-#{tag}-#{target}.tar.gz"
      asset = assets.find { |a| a["name"] == expected }
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

  # --- versioned formula creation --------------------------------------------

  def ensure_versioned_formula!(major, minor)
    path = "Formula/kakehashi@#{major}.#{minor}.rb"
    return if File.exist?(path)

    klass = class_name_for(major, minor)
    template = Dir["Formula/kakehashi@*.rb"]
               .max_by { |p| Gem::Version.new(File.basename(p, ".rb").sub(/^kakehashi@/, "")) }
    src = File.read(template || "Formula/kakehashi.rb")
    src = src.sub(/^class \w+ < Formula/, "class #{klass} < Formula")
    src = src.sub(/^\s*livecheck do\n.*?\n\s*end\n/m, "") if src.include?("livecheck do")
    unless src.include?("keg_only :versioned_formula")
      src = src.sub(/(  license [^\n]+\n)/, "\\1\n  keg_only :versioned_formula\n")
    end
    File.write(path, src) unless DRY_RUN
    path
  end

  # --- main orchestration ----------------------------------------------------

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
    end

    target_json.each_key do |key|
      next if key == ""

      parts = key.split(".")
      created_path = ensure_versioned_formula!(parts[0].to_i, parts[1].to_i)
      report[:changed] = true if created_path
    end

    write_report(report)
  end

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

  # --- self-test -------------------------------------------------------------

  def self_test
    failures = []

    cases = {
      "v0.5.0"      => Gem::Version.new("0.5.0"),
      "v1.2.3"      => Gem::Version.new("1.2.3"),
      "v10.20.30"   => Gem::Version.new("10.20.30"),
      "0.5.0"       => nil,
      "v0.5"        => nil,
      "v0.5.0-rc.1" => nil,
      "v0.5.0+b1"   => nil,
      "invalid"     => nil,
      ""            => nil,
    }
    cases.each do |tag, expected|
      got = parse_semver(tag)
      failures << "parse_semver(#{tag.inspect}) => #{got.inspect}, expected #{expected.inspect}" if got != expected
    end

    class_cases = {
      [0, 1]  => "KakehashiAT01",
      [0, 4]  => "KakehashiAT04",
      [0, 5]  => "KakehashiAT05",
      [1, 0]  => "KakehashiAT10",
      [0, 10] => "KakehashiAT010",
    }
    class_cases.each do |(major, minor), expected|
      got = class_name_for(major, minor)
      if got != expected
        failures << "class_name_for(#{major}, #{minor}) => #{got.inspect}, expected #{expected.inspect}"
      end
    end

    if failures.empty?
      puts "ok (#{cases.size + class_cases.size} assertions)"
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
  when nil
    FormulaUpdater.run_updater
  else
    warn "usage: #{$PROGRAM_NAME} [--self-test | --probe <tag>]"
    exit 2
  end
end
