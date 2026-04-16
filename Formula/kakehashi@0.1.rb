require "json"

class KakehashiAT01 < Formula
  desc "Language server bridging the gap between languages, editors, and tooling"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  keg_only :versioned_formula

  versions = JSON.parse(File.read(File.join(__dir__, "versions.json")))
  vkey = File.basename(__FILE__, ".rb").delete_prefix("kakehashi").delete_prefix("@")
  vdata = versions.fetch(vkey)

  on_macos do
    on_arm do
      url vdata.dig("macos", "arm", "url")
      sha256 vdata.dig("macos", "arm", "sha256")
    end
    on_intel do
      url vdata.dig("macos", "intel", "url")
      sha256 vdata.dig("macos", "intel", "sha256")
    end
  end

  on_linux do
    on_arm do
      url vdata.dig("linux", "arm", "url")
      sha256 vdata.dig("linux", "arm", "sha256")
    end
    on_intel do
      url vdata.dig("linux", "intel", "url")
      sha256 vdata.dig("linux", "intel", "sha256")
    end
  end

  def install
    bin.install "kakehashi"
  end

  test do
    assert_match(/\Akakehashi #{Regexp.escape(version.to_s)}\b/,
                 shell_output("#{bin}/kakehashi --version"))
  end
end
