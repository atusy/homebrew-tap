class KakehashiAT03 < Formula
  desc "Language server bridging the gap between languages, editors, and tooling"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  keg_only :versioned_formula

  on_macos do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.3.0/kakehashi-v0.3.0-aarch64-apple-darwin.tar.gz"
      sha256 "b6e331fb19012e1f1dc9086f078a422a311df59920f827251db55ec4567c6574"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.3.0/kakehashi-v0.3.0-x86_64-apple-darwin.tar.gz"
      sha256 "35d9a4cc093a841821bbff60989d50c0602e3d2eeeecaf98136c6816bdb793a3"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.3.0/kakehashi-v0.3.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "96007f27f15e065925035a92e21806ba9d79ba5ce1d774262a7ad40ce9f12982"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.3.0/kakehashi-v0.3.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "a612a5c530e34adc542e2a769e1c25ea6821e60e8021fa2fc2dcb5f68f66d37a"
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
