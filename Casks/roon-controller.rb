cask "roon-controller" do
  version "1.2.4"
  sha256 "d81e383cda53ba26638acd9eb5e430e36d61c0700a39533ba16aedac159a614f"

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
