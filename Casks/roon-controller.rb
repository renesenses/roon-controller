cask "roon-controller" do
  version "1.2.0"
  sha256 "e7c245049305cda5985c1da46562ed667c34c62d061c37720ec500e55cfcb85b"

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
