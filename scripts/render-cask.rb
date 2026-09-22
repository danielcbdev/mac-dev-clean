# Generates Casks/macdevclean.rb from validated release inputs.
#
# It is a separate file, invoked with five literal arguments, so no caller can
# interpolate shell text into Ruby source. Every argument is validated against
# an exact shape before it reaches the template, and an existing output file is
# never overwritten.
#
# The cask installs the app and nothing else. There is deliberately no `zap`
# stanza and no uninstall script: a cask uninstall must remove MacDevClean, not
# the caches, projects, Trash or cleanup history on the machine.

owner, repo, release_version, checksum, output = ARGV
abort "Expected five arguments" unless ARGV.length == 5
abort "Invalid owner" unless owner.match?(/\A[A-Za-z0-9][A-Za-z0-9-]*\z/)
abort "Invalid repository" unless repo.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/)
abort "Invalid version" unless release_version.match?(/\A\d+\.\d+\.\d+\z/)
abort "Invalid checksum" unless checksum.match?(/\A[0-9a-f]{64}\z/)
abort "Output exists" if File.exist?(output)

text = <<~CASK
  cask "macdevclean" do
    version "#{release_version}"
    sha256 "#{checksum}"
    url "https://github.com/#{owner}/#{repo}/releases/download/v#{release_version}/MacDevClean-#{release_version}.dmg"
    name "MacDevClean"
    desc "Inspect and clean developer storage on macOS"
    homepage "https://github.com/#{owner}/#{repo}"
    depends_on macos: ">= :sonoma"
    app "MacDevClean.app"
  end
CASK
File.write(output, text)
