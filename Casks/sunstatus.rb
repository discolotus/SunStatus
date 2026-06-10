cask "sunstatus" do
  version "0.4.0"
  sha256 "d73dea7c9f0b483d28191ea7f9a4d4276004de96060086a8ce5e5f3043f6fd80"

  url "https://github.com/discolotus/SunStatus/releases/download/v#{version}/SunStatus.dmg"
  name "SunStatus"
  desc "Menu bar sun status, daylight, and 3D sun-path map"
  homepage "https://github.com/discolotus/SunStatus"

  depends_on macos: :sonoma

  app "SunStatus.app"

  zap trash: [
    "~/Library/Application Support/SunStatus",
    "~/Library/Caches/com.discolotus.SunStatus",
    "~/Library/Preferences/com.discolotus.SunStatus.plist",
    "~/Library/Saved Application State/com.discolotus.SunStatus.savedState",
  ]

  caveats do
    <<~EOS
      SunStatus is currently ad-hoc signed. Until Developer ID signing and
      notarization are in place, macOS may require Control-click > Open for
      first launch.
    EOS
  end
end
