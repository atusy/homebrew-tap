class Kakehashi < Formula
  desc "LSP server using Tree-sitter for language-aware features"
  homepage "https://github.com/atusy/kakehashi"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.5.0/kakehashi-v0.5.0-aarch64-apple-darwin.tar.gz"
      sha256 "49f4c4039b8f95796e46d2d55e83c9ef79b65098cddc4970aa710fa7ecd20e91"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.5.0/kakehashi-v0.5.0-x86_64-apple-darwin.tar.gz"
      sha256 "5b5f8c5c7612623163f10a8a9885ed21ab7f76a93adb9eea747e95f2709d0496"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/atusy/kakehashi/releases/download/v0.5.0/kakehashi-v0.5.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "616dc1256c7a1a28e695254efad316ac0dc9c89f9aedfafa6df5b23a56643f2f"
    end
    on_intel do
      url "https://github.com/atusy/kakehashi/releases/download/v0.5.0/kakehashi-v0.5.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "fcee5c6bba39946efab05a3ee08068544e716ed73c818044c659b37e131a215a"
    end
  end

  def install
    bin.install "kakehashi"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/kakehashi --version")
  end
end
