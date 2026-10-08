class OpenWispr < Formula
  desc "Push-to-talk voice dictation for macOS using Whisper"
  homepage "https://github.com/human37/open-wispr"
  url "https://github.com/human37/open-wispr.git", tag: "v0.9.1"
  license "MIT"

  depends_on "whisper-cpp"
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    system "bash", "scripts/bundle-app.sh", ".build/release/open-wispr", "OpenWispr.app", version.to_s
    bin.install ".build/release/open-wispr"
    prefix.install "OpenWispr.app"
  end

  def post_install
    target = Pathname.new("#{Dir.home}/Applications/OpenWispr.app")
    target.dirname.mkpath
    target.rmtree if target.exist?
    cp_r prefix/"OpenWispr.app", target
    system "codesign", "--remove-signature", "#{target}/Contents/MacOS/open-wispr"
    system "tccutil", "reset", "Accessibility", "com.human37.open-wispr"
  end

  service do
    run ["#{Dir.home}/Applications/OpenWispr.app/Contents/MacOS/open-wispr", "start"]
    keep_alive successful_exit: false
    log_path var/"log/open-wispr.log"
    error_log_path var/"log/open-wispr.log"
    process_type :interactive
  end

  def caveats
    <<~EOS
      This Homebrew formula installs the upstream release. To install the
      fork-specific menu, overlay, and login behavior, build this repository:
        git clone https://github.com/zhaoyanthu/open-wispr.git
        cd open-wispr && ./scripts/install-from-source.sh

      Grant Microphone and Accessibility access when macOS asks.
    EOS
  end

  test do
    assert_match "open-wispr", shell_output("#{bin}/open-wispr --help")
  end
end
