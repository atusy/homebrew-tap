class KakehashiAT02 < Formula
  desc "Language server bridging the gap between languages, editors, and tooling"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  keg_only :versioned_formula

  on_macos do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.2.0/kakehashi-v0.2.0-aarch64-apple-darwin.tar.gz"
      sha256 "a7d85eb1684414a44190d4c51aa63f9ca8f02a9e943ded7dcbcf818b5766314c"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.2.0/kakehashi-v0.2.0-x86_64-apple-darwin.tar.gz"
      sha256 "d430f0288902d0546a76d9718626fc173f8f712b027163206eac5ef6f7fb7839"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.2.0/kakehashi-v0.2.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "1011c74a4224e44d8a8087c65824579989c0bf9e433c00cb8cb0df373fd019f2"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.2.0/kakehashi-v0.2.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "655782edf1722a0b7fed8693bbec5db3f38d36f7ee9dc40aca13393eda7951c6"
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
