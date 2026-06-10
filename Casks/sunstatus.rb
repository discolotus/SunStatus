cask "sunstatus" do
  version "0.4.0"
  sha256 "4576ac7ff4175e8fb028b1647e23f5af0fe0a06b1e7370a3fa610dd9b4b880bb"

  url "https://github.com/discolotus/SunStatus/releases/download/v#{version}/SunStatus.dmg"
  name "SunStatus"
  desc "Menu bar sun status, daylight, and 3D sun-path map"
  homepage "https://github.com/discolotus/SunStatus"

  app "SunStatus.app"

  caveats do
    <<~EOS
      SunStatus is currently ad-hoc signed. Until Developer ID signing and
      notarization are in place, macOS may require Control-click > Open for
      first launch.
    EOS
  end

  zap trash: [
    "~/Library/Preferences/com.discolotus.SunStatus.plist",
    "~/Library/Saved Application State/com.discolotus.SunStatus.savedState",
  ]
end
