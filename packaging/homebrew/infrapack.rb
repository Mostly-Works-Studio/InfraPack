# Homebrew formula for InfraPack. Lives in the tap repository
# github.com/Mostly-Works-Studio/homebrew-tap as Formula/infrapack.rb;
# scripts/release.sh fills in the version and sha256 and copies it there.
#
#   brew install mostly-works-studio/tap/infrapack
#
# Written to homebrew-core standards (source install, license, test block, no
# explicit version) so the same file can be submitted to Homebrew/homebrew-core
# once the project meets their notability bar.
class Infrapack < Formula
  desc "Local development infrastructure, one command: databases, brokers, caches with web UIs"
  homepage "https://github.com/Mostly-Works-Studio/infrapack"
  url "https://github.com/Mostly-Works-Studio/infrapack/archive/refs/tags/v__VERSION__.tar.gz"
  sha256 "__SHA256__"
  license "MIT"

  # Pure bash; Docker is found at runtime and reported by `infrapack doctor`.
  def install
    libexec.install Dir["*"]
    chmod 0755, libexec/"bin/infrapack"
    bin.install_symlink libexec/"bin/infrapack"
  end

  def caveats
    <<~EOS
      InfraPack needs Docker (Docker Desktop, OrbStack or Colima on macOS).
      Then:
        infrapack catalog            # what can be installed
        infrapack install postgres   # add one and start it
        infrapack open               # the web console
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/infrapack version")
  end
end
