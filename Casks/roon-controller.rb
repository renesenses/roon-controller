cask "roon-controller" do
  version "1.2.1"
  sha256 "c16a61359a2c7b113d03a768bcb322330f417d53f0bef6e1087d90b295bb16e0"

  url "https://github.com/renesenses/roon-controller/releases/download/v#{version}/RoonController.dmg"
  name "Roon Controller"
  desc "Native macOS remote control for Roon"
  homepage "https://github.com/renesenses/roon-controller"

  depends_on macos: ">= :monterey"

  app "Roon Controller.app"

  zap trash: [
    "~/Library/Preferences/com.bertrand.RoonController.plist",
    "~/Library/Saved Application State/com.bertrand.RoonController.savedState",
  ]

  caveats <<~EOS
    #{token} is not signed with an Apple Developer ID.
    On first launch, run: xattr -cr "/Applications/Roon Controller.app"
    Or go to System Settings > Privacy & Security > Open Anyway.
    Then authorize "Roon Controller macOS" in Roon > Settings > Extensions.
  EOS
end
