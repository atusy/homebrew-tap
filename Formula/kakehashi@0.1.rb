class KakehashiAT01 < Formula
  desc "Language server bridging the gap between languages, editors, and tooling"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.1.0/kakehashi-v0.1.0-aarch64-apple-darwin.tar.gz"
      sha256 "731d223ecd5270e0c685dae6716e2e9068ceaea25fe7143cb061c6cb11e5daa3"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.1.0/kakehashi-v0.1.0-x86_64-apple-darwin.tar.gz"
      sha256 "06dc01fade0a811f96398be77c0795534759ead5d4ae9a334de54e82ac22e18c"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.1.0/kakehashi-v0.1.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "11809bbbdb35299b41c85284f0597a70605b8320addc93f6aab30d16e2ba16be"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.1.0/kakehashi-v0.1.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "95d9d440dc3089c1ba9077825939f6b6dc839a5fad1f86de53d53f4c3a89d237"
    end
  end

  keg_only :versioned_formula

  def install
    bin.install "kakehashi"
  end

  test do
    assert_match(/\Akakehashi #{Regexp.escape(version.to_s)}\b/,
                 shell_output("#{bin}/kakehashi --version"))
  end
end
