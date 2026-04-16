class KakehashiAT04 < Formula
  desc "Language server bridging the gap between languages, editors, and tooling"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.4.1/kakehashi-v0.4.1-aarch64-apple-darwin.tar.gz"
      sha256 "9ef597c6ab16a17e8db142dad2a4b1ed315e32582277985de3f91e2b4c0612d9"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.4.1/kakehashi-v0.4.1-x86_64-apple-darwin.tar.gz"
      sha256 "885c1795e1710433ba851514665764d0947fd4f466119859e32059eaa7a6b477"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.4.1/kakehashi-v0.4.1-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "9847bdd0beff3f64e986211bbdc170f2a4558de2cb2e29000c909d6cf2851c89"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.4.1/kakehashi-v0.4.1-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "0c54955d12c1678aaf358cc8b67bbdb762b72b12bd0f6269a69cf481a7b6bd1a"
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
