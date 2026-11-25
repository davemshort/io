#!/bin/zsh -f
emulate -L zsh
setopt err_exit pipefail
unsetopt bg_nice
export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
(( EUID != 0 )) || { print -u2 'Run the fixture suite as a regular user.'; exit 1; }
readonly source_dir=${0:A:h:h}
readonly work=$(mktemp -d /private/tmp/io-tests.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT

fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() {
    local expected=$1 needle=$2 actual=0
    shift 2
    output=$("$@" </dev/null 2>&1) || actual=$?
    [[ $actual == "$expected" && $output == *"$needle"* ]] ||
        fail "$*: expected exit $expected and '$needle', got exit $actual and '$output'"
}

readonly project="$work/checkout with spaces"
mkdir -p "$project"/{bin,lib,scripts} "$work/system/opt" "$work/system/usr/local"
cp "$source_dir"/{VERSION,LICENSE} "$project"
cp "$source_dir"/scripts/*.sh "$project/scripts"
cp "$source_dir/lib/trust.zsh" "$project/lib"
cp "$source_dir/tests/mock-installomator" "$work/mock engine"
export HOME="$work/home" XDG_CONFIG_HOME="$work/config with spaces" XDG_CACHE_HOME="$work/cache with spaces"
readonly io="$project/bin/io" config="$XDG_CONFIG_HOME/io/config"
readonly apps="$XDG_CONFIG_HOME/io/apps.txt" cache="$XDG_CACHE_HOME/io/labels.txt"

cat > "$work/sudo" <<'MOCK'
#!/bin/zsh -f
[[ $1 != -n ]] || shift
if [[ $* == '-v' ]]; then
    [[ ${MOCK_SUDO_DENY:-} != 1 ]]
    exit $?
fi
[[ $1 == -- ]] || exit 90
shift
if [[ $1 == /usr/sbin/installer ]]; then
    [[ $# == 5 && $2 == -pkg && -f $3 && $4 == -target && $5 == / ]] || exit 90
    print 'installer called' >> "$MOCK_ENGINE_ACTIONS"
    /usr/bin/sed -i '' 's/^VERSION="10.10"$/VERSION="10.11"/' "$MOCK_DEFAULT_ENGINE"
    exit $?
fi
exec "$@"
MOCK
cat > "$work/curl" <<'MOCK'
#!/bin/zsh -f
case ${@[-1]} in
    https://api.github.com/repos/rxhanson/Rectangle/releases/latest)
        [[ ${MOCK_LATEST:-} != offline ]] || exit 6
        printf '{"tag_name":"%s"}\n' "${MOCK_LATEST:-v1.24}"
        exit 0 ;;
    https://api.github.com/repos/Installomator/Installomator/releases/latest)
        cp "$MOCK_ENGINE_RELEASE" "${argv[$(( argv[(i)--output] + 1 ))]}"
        exit $? ;;
    https://github.com/Installomator/Installomator/releases/download/v10.11/Installomator-10.11.pkg)
        if [[ -t 2 && ${TERM:-dumb} != dumb ]]; then
            [[ $* == *--progress-bar* && $* != *--silent* ]] || exit 90
            print -ru2 -- '############################## 100.0%'
        else
            [[ $* == *--silent* && $* != *--progress-bar* ]] || exit 90
        fi
        cp "$MOCK_ENGINE_PACKAGE" "${argv[$(( argv[(i)--output] + 1 ))]}"
        exit $? ;;
esac
[[ ${@[-1]} == https://raw.githubusercontent.com/Installomator/Installomator/${MOCK_TAG}/Labels.txt ]] || exit 90
[[ ${MOCK_NETWORK:-} != offline ]] || exit 6
if [[ ${MOCK_NETWORK:-} == malformed ]]; then
    print '<html>bad response</html>'
else
    print -l remote-label valuesfromarguments
fi
MOCK
cat > "$work/brew" <<'MOCK'
#!/bin/zsh -f
case $1 in
    list)
        [[ $# == 3 && $2 == --cask && $3 == -1 ]] || exit 90
        /bin/cat "$MOCK_CASKS" ;;
    info)
        [[ $# == 4 && $2 == --cask && $3 == --json=v2 && $4 == --installed ]] || exit 90
        print -r -- '{"casks":[{"token":"brave","artifacts":[{"app":["Brave Browser.app"],"target":"/Applications/Brave Browser.app"},{"binary":["brave"],"target":"/opt/homebrew/bin/brave"},{"uninstall":[{"launchctl":["com.brave.agent"]}]},{"zap":[{"trash":["hidden-preferences"]}]}]}]}'
        ;;
    uninstall)
        [[ $# == 3 && $2 == --cask ]] || exit 90
        print -r -- "$3" >> "$MOCK_REMOVED"
        print -r -- "==> Uninstalling Cask $3"
        [[ ${MOCK_BREW_FAIL:-} != "$3" ]] ;;
    *) exit 90 ;;
esac
MOCK
cat > "$work/spctl" <<'MOCK'
#!/bin/zsh -f
[[ $* == *'--assess --type install --verbose=4'* && -f ${@[-1]} ]] || exit 90
print 'source=Notarized Developer ID'
MOCK
cat > "$work/pkgutil" <<'MOCK'
#!/bin/zsh -f
case $1 in
    --pkg-info) [[ $2 == com.scriptingosx.Installomator ]] ;;
    --check-signature)
        [[ -f $2 ]] || exit 90
        print -r -- "    1. Developer ID Installer: Fixture (${MOCK_SIGNER:-JME5BW3F3R})" ;;
    *) exit 90 ;;
esac
MOCK
chmod +x "$work/sudo" "$work/curl" "$work/brew" "$work/spctl" "$work/pkgutil"
# Rebind absolute command paths in a disposable copy. Production has no test overrides.
sed -e "s|/usr/bin/sudo|$work/sudo|g" -e "s|/usr/bin/curl|$work/curl|g" \
    -e "s|/opt/homebrew/bin/brew|$work/brew|g" \
    -e "s|/usr/sbin/pkgutil|$work/pkgutil|g" -e "s|/usr/sbin/spctl|$work/spctl|g" \
    -e "s|/usr/local/Installomator/Installomator.sh|$work/missing|g" "$source_dir/bin/io" > "$io"
chmod +x "$io"
check 0 'Usage:' "$io" --help
check 2 'requires one' "$io" add
check 2 'Invalid' "$io" install 'brave;id'
check 2 'reserved' "$io" install valuesfromarguments
check 1 'unavailable' "$io" install brave
check 0 '' "$io" list
[[ ! -e $XDG_CONFIG_HOME && ! -e $XDG_CACHE_HOME ]] || fail 'unexpected directory creation'
export MOCK_TAG=release MOCK_NETWORK=offline
check 1 'cache was preserved' "$io" available
export MOCK_NETWORK=malformed
check 1 'Invalid catalog content' "$io" refresh
export MOCK_NETWORK=online
check 0 remote-label "$io" available
[[ $output == remote-label ]] || fail 'reserved remote label leaked'
before=$(< "$cache")
export MOCK_NETWORK=offline
check 1 'cache was preserved' "$io" refresh
[[ $(< "$cache") == "$before" ]] || fail 'refresh changed valid cache'
check 0 remote-label "$io" available
print broken > "$cache"
check 1 'Invalid catalog cache' "$io" doctor
check 1 'cache was preserved' "$io" available

mkdir -p "${config:h}"
print -rl -- '# literal configuration' '   ' "installomator_path=$work/mock engine" > "$config"
check 0 'Installomator 10.10' "$io" --version
check 0 brave-alias "$io" search BRAVE
[[ $output == $'brave\nbrave-alias\nbrave-other' ]] || fail 'incomplete multiline aliases'
check 1 '' "$io" search ':('
check 1 'Unknown application label' "$io" add absent
check 1 'Refusing to elevate' "$io" install brave
check 0 'Unregistered' "$io" info brave
print -l brave brave current > "$apps"
check 0 $'brave\ncurrent' "$io" list
[[ $output == $'brave\ncurrent' ]] || fail 'list must emit plain deduplicated labels'
fixture_plist="$HOME/Applications/Fixture Brave.app/Contents/Info.plist"
mkdir -p "${fixture_plist:h}"
cat > "$fixture_plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>test.io.brave</string>
<key>CFBundleShortVersionString</key><string>1.23</string>
</dict></plist>
PLIST
check 0 '1.23' "$io" list --installed
[[ $output == *'brave'*'Installed'*'1.23'*'current'*'Not found'* ]] || fail 'local bundle inventory'
mkdir -p "$HOME/Applications/Fixture Rectangle.app/Contents"
cp "$fixture_plist" "$HOME/Applications/Fixture Rectangle.app/Contents/Info.plist"
check 0 'Registered' "$io" add rectangle
check 0 '1 outdated' "$io" outdated rectangle
[[ $output == *'1.23'*'1.24'*'Outdated'* ]] || fail 'outdated version comparison'
check 0 'Up to date' env MOCK_LATEST=v1.23 "$io" outdated rectangle
check 0 'Up to date' env MOCK_LATEST=v1.22 "$io" outdated rectangle
check 0 'Unknown (release lookup unavailable)' env MOCK_LATEST=offline "$io" outdated rectangle
check 0 'Unknown (release lookup unavailable)' env MOCK_LATEST=v1.24-beta "$io" outdated rectangle
check 0 'Unknown (no release source)' "$io" outdated brave
check 0 'Not found' "$io" outdated current
check 1 'is not registered' "$io" outdated unknown-app
check 0 'Deregistered' "$io" remove rectangle

# Simulate administrator ownership only inside the disposable fixture tree.
uid=$(id -u)
sed -e "s|== '0 '|== '$uid '|" -e "s|== / ]]|== $work ]]|" \
    "$source_dir/lib/trust.zsh" > "$project/lib/trust.zsh"
chmod g+w "$work/mock engine"
check 1 'Refusing to elevate' "$io" install brave
chmod g-w "$work/mock engine"
chmod +a "$(id -un) allow write" "$work/mock engine"
check 1 'Refusing to elevate' "$io" install brave
chmod -N "$work/mock engine"

check 0 'Deployment completed' "$io" brave
check 0 'Already current' "$io" update current
check 0 'Deployment completed' "$io" update brave
[[ $output == *'==> Updating brave'*'==> Downloading installer'*'==> Verifying installer'*'==> brave: Deployment completed'* ]] ||
    fail 'deployment progress missing or out of order'
[[ $output == *'==> Preparing installation'* && $output != *'==> Preparing installation'*'==> Preparing installation'* ]] ||
    fail 'expected exactly one preparation heading'
[[ $output != *$'\e['* ]] || fail 'redirected output contains color'
check 0 'Deployment completed' env TERM=xterm-256color NO_COLOR= \
    /usr/bin/script -q /dev/null /bin/zsh -fc 'exec "$@" </dev/null' zsh "$io" update brave
[[ $output == *$'\e[1;32m==>\e[0m Updating \e[1;32mbrave\e[0m'* &&
   $output == *$'\e[1;34m==>\e[0m Downloading installer'* &&
   $output == *$'\e[1;32m==>\e[0m brave: Deployment completed'* ]] || fail 'terminal output is missing colors'
check 0 'Deployment completed' env TERM=xterm-256color NO_COLOR=1 \
    /usr/bin/script -q /dev/null /bin/zsh -fc 'exec "$@" </dev/null' zsh "$io" update brave
[[ $output != *$'\e['* ]] || fail 'NO_COLOR did not disable colors'
output=$(env TERM=xterm-256color NO_COLOR= /usr/bin/script -q /dev/null /bin/zsh -fc '
    "$1" install blocked </dev/null
    "$1" update invalid-label </dev/null
    "$1" --version
' zsh "$io" </dev/null)
[[ $output == *$'\e[1;33m==> Warning:\e[0m blocked: Skipped'* &&
   $output == *$'\e[1;31m==> Error:\e[0m invalid-label is not registered'* &&
   $output == *$'\e[1;34m==>\e[0m io '* ]] || fail 'diagnostic and status colors are missing'
check 1 '==> Error: invalid-label is not registered' "$io" update invalid-label
[[ $output != *$'\e['* ]] || fail 'redirected error contains color'
check 3 'Skipped (Installomator exit 12)' "$io" install blocked
check 1 'download failed' "$io" install broken
check 1 'Installomator exit 1' "$io" install badlabel
check 1 'Installomator exit 42' "$io" install unexpected
check 3 'Outcome unknown' "$io" install ambiguous
check 3 'can terminate Acrobat Updater' "$io" install adobereaderdc
check 0 $'brave\ncurrent' "$io" list
[[ $output == $'brave\ncurrent' ]] || fail 'unconfirmed deployment changed registry'
check 0 Registered "$io" add brave
check 0 Deregistered "$io" remove brave
check 0 'Deployment completed' "$io" install brave
[[ $output == *'==> Installing brave'* ]] || fail 'missing install heading'
check 0 'Registry: Registered' "$io" info brave
check 0 'Already current' "$io" install current
batch_config="$work/batch config"
mkdir -p "$batch_config/io"
cp "$config" "$batch_config/io/config"
check 1 'Unknown application label: absent' env XDG_CONFIG_HOME="$batch_config" "$io" install brave absent
[[ $output != *'==> Installing brave'* && ! -e $batch_config/io/apps.txt ]] || fail 'invalid batch performed a deployment'
check 2 'Invalid or reserved' env XDG_CONFIG_HOME="$batch_config" "$io" install brave --oops
check 1 '1 completed, 1 current, 1 skipped, 1 failed, 1 unknown' \
    env XDG_CONFIG_HOME="$batch_config" "$io" install broken BRAVE brave blocked ambiguous current
[[ $output == *'==> Installing broken'*'==> Installing brave'*'==> Installing current'* &&
   $output != *'==> Installing brave'*'==> Installing brave'* ]] || fail 'batch order or duplicate deployment'
check 0 $'brave\ncurrent' env XDG_CONFIG_HOME="$batch_config" "$io" list
[[ $output == $'brave\ncurrent' ]] || fail 'batch registered an unconfirmed deployment'
check 3 '1 completed, 0 current, 1 skipped, 0 failed, 0 unknown' \
    env XDG_CONFIG_HOME="$batch_config" "$io" install blocked brave-alias
check 0 Registered "$io" add same-download
check 0 'Already current' "$io" update same-download
check 0 Deregistered "$io" remove same-download

printf '%s\n' blocked broken ambiguous | /usr/bin/xargs -P 3 -n 1 "$io" add >/dev/null
check 1 '1 completed, 1 current, 1 skipped, 1 failed, 1 unknown' "$io" update --all
check 0 'Deregistered' "$io" remove broken
check 3 '1 completed, 1 current, 1 skipped, 0 failed, 1 unknown' "$io" update --all

export MOCK_CASKS="$work/installed-casks" MOCK_REMOVED="$work/removed-casks"
print -rl -- 'old-app@2' blocked current missing-label brave ringcentral visual-studio-code > "$MOCK_CASKS"
check 0 'Replace: brave -> brave' "$io" replace brave
[[ $output == *'Preview only. Pass -y'* && $output != *'[Y/n]'* ]] || fail 'non-interactive confirmation'
check 0 'Replace: old-app@2 -> brave' "$io" replace 'old-app@2' --label brave
check 0 'Excluded: brave' "$io" replace --all --exclude brave --exclude current --map 'old-app@2=brave'
[[ $output == *'Excluded: current'* && $output == *'Unmatched: missing-label'* &&
   $output == *'Replace: old-app@2 -> brave'* && ! -e $MOCK_REMOVED ]] || fail 'bulk preview'
check 2 'requires cask=label' "$io" replace --all --map invalid
check 1 'is not installed' "$io" replace --all --exclude typo -y
check 1 'map to brave' "$io" replace --all --map 'old-app@2=brave' -y
check 1 'No deployable' "$io" replace brave --label adobereaderdc -y
check 1 'Could not authorize' env MOCK_SUDO_DENY=1 "$io" replace brave -y
check 1 '1) ringcentralapp' "$io" replace ringcentral -y
[[ $output == *'2) ringcentralphone'* && $output != *'[Y/n]'* ]] || fail 'unattended suggestion list'
check 1 '1) visualstudiocode' "$io" replace visual-studio-code
check 1 'No deployable Installomator label for missing-label.' "$io" replace missing-label
[[ ! -e $MOCK_REMOVED ]] || fail 'failed preflight removed a cask'
confirm_replace() {
    /usr/bin/expect -f - "$io" "$1" <<'EXPECT'
set timeout 10
set mode [lindex $argv 1]
if {$mode eq "suggestion"} {
    spawn -noecho [lindex $argv 0] replace ringcentral
    expect -exact {Choose a label (Enter to cancel):}
    send -- "1\r"
} else {
    spawn -noecho [lindex $argv 0] replace brave
}
expect -exact {[Y/n]}
if {$mode eq "suggestion"} {
    send -- "n\r"
} elseif {$mode eq "decline"} {
    send -- "maybe\r"
    expect -exact {Please answer yes or no.}
    expect -exact {[Y/n]}
    send -- "n\r"
} else {
    send -- "\r"
}
expect eof
exit [lindex [wait] 3]
EXPECT
}
output=$(confirm_replace suggestion)
[[ $output == *'Replace: ringcentral -> ringcentralapp'*'[Y/n]'*'Replacement cancelled.'* &&
   ! -e $MOCK_REMOVED ]] || fail 'suggestion did not require confirmation'
output=$(confirm_replace decline)
[[ $output == *'Replace: brave -> brave'*'Proceed with replacement? [Y/n]'*'Please answer yes or no.'*'Replacement cancelled.'* &&
   ! -e $MOCK_REMOVED ]] || fail 'interactive cancellation removed a cask or missed the prompt'
output=$(confirm_replace accept)
[[ $output == *'Proceed with replacement? [Y/n]'*'Replaced 1 Homebrew cask(s).'* &&
   $(< "$MOCK_REMOVED") == brave ]] || fail 'Enter did not accept the default'
rm "$MOCK_REMOVED"
check 1 'brew install --cask brave' env MOCK_BREW_FAIL=brave "$io" replace brave -y
[[ $output != *'==> io: Installing brave'* ]] || fail 'deployment started after unsuccessful uninstall'
rm "$MOCK_REMOVED"
check 0 'Replaced 1 Homebrew cask(s).' "$io" replace 'old-app@2' --label brave-alias -y
[[ $output != *'[Y/n]'* ]] || fail '-y prompted for confirmation'
[[ $output == *'==> Homebrew: Removing cask old-app@2'*'==> Uninstalling Cask old-app@2'$'\n\n''==> io: Installing brave-alias'* ]] ||
    fail 'missing Homebrew and io phase headings'
[[ $(< "$MOCK_REMOVED") == 'old-app@2' ]] || fail 'wrong cask removed'
check 0 'Registry: Registered' "$io" info brave-alias
rm "$MOCK_REMOVED"
check 0 'Deregistered' "$io" remove blocked
check 3 'brew install --cask blocked' "$io" replace --all --exclude brave --map 'old-app@2=brave' -y
[[ $(< "$MOCK_REMOVED") == $'old-app@2\nblocked' ]] || fail 'bulk migration did not stop'
check 0 'Registry: Unregistered' "$io" info blocked
rm "$MOCK_REMOVED"
print -rl -- brave current 'old-app@2' missing-label > "$MOCK_CASKS"
check 0 'Replaced 2 Homebrew cask(s).' "$io" replace --all --exclude 'old-app@2' -y
[[ $(< "$MOCK_REMOVED") == $'brave\ncurrent' ]] || fail 'successful bulk migration ignored its plan'
rm "$MOCK_REMOVED"
check 0 'Remove CLI entry "/opt/homebrew/bin/brave"' "$io" replace brave 'old-app@2' --map 'old-app@2=current' --dry-run
[[ $output == *'==> Replace: old-app@2 -> current'* && $output == *'==> Homebrew uninstall preview (declared actions)'* &&
   $output == *'- Remove launch service "com.brave.agent"'* &&
   $output != *hidden-preferences* && ! -e $MOCK_REMOVED ]] || fail 'selected uninstall preview'
check 1 'Add --map' "$io" replace brave 'old-app@2' -y
[[ ! -e $MOCK_REMOVED ]] || fail 'unmapped selected cask allowed partial migration'
check 0 'Replaced 2 Homebrew cask(s).' "$io" replace brave 'old-app@2' --map 'old-app@2=current' -y
[[ $(< "$MOCK_REMOVED") == $'brave\nold-app@2' ]] || fail 'selected migration ignored order'

export MOCK_DEFAULT_ENGINE="$work/missing" MOCK_ENGINE_RELEASE="$work/release.json"
export MOCK_ENGINE_PACKAGE="$work/package.pkg" MOCK_ENGINE_ACTIONS="$work/engine-actions"
cp "$work/mock engine" "$MOCK_DEFAULT_ENGINE"
print -r -- "installomator_path=$MOCK_DEFAULT_ENGINE" > "$config"
print -r -- 'fixture package' > "$MOCK_ENGINE_PACKAGE"
digest=$(shasum -a 256 "$MOCK_ENGINE_PACKAGE")
digest=${digest%% *}
engine_release() {
    printf '{"tag_name":"v%s","draft":false,"prerelease":false,"assets":[{"name":"Installomator-%s.pkg","digest":"sha256:%s"}]}\n' \
        "$1" "$1" "$2" > "$MOCK_ENGINE_RELEASE"
}
engine_release 10.9 "$digest"
check 0 'No upgrade needed' "$io" upgrade-engine -y
engine_release 10.11 "$digest"
check 0 'Latest stable: 10.11' "$io" upgrade-engine --check
check 0 'Check only' "$io" upgrade-engine
engine_release 10.11 "${(l:64::0:)}"
check 1 'checksum mismatch' "$io" upgrade-engine -y
[[ $output != *'100.0%'* ]] || fail 'redirected engine upgrade showed a transfer meter'
engine_release 10.11 "$digest"
check 1 'Developer ID verification' env MOCK_SIGNER=BADTEAM123 "$io" upgrade-engine -y
[[ ! -e $MOCK_ENGINE_ACTIONS ]] || fail 'unverified engine package reached installer'
check 0 'Installomator upgraded to 10.11' env TERM=xterm-256color \
    /usr/bin/script -q /dev/null /bin/zsh -fc 'exec "$@" </dev/null' zsh "$io" upgrade-engine -y
[[ $output == *'Downloading Installomator 10.11'*'100.0%'*'Verifying Installomator package'* ]] ||
    fail 'terminal engine upgrade did not show download progress'
check 0 'No upgrade needed' "$io" upgrade-engine --check
[[ $(< "$MOCK_ENGINE_ACTIONS") == 'installer called' && $(< "$cache") == *10.11* ]] ||
    fail 'upgrade did not install once and refresh catalog'

print -r -- INVALID > "$apps"
check 1 'Invalid label' "$io" list
print -r -- 'installomator_path=$(touch SHOULD_NOT_EXIST)' > "$config"
check 1 'Invalid configuration' "$io" refresh
print -r -- "installomator_path=$work/older engine" > "$config"
printf '#!/bin/zsh -f\nVERSION="10.8"\n' > "$work/older engine"
chmod +x "$work/older engine"
export MOCK_TAG=v10.8 MOCK_NETWORK=online
check 0 'v10.8 catalog' "$io" refresh
check 0 remote-label "$io" available

# Exercise the maintenance scripts under an isolated prefix, with ownership re-bound.
readonly opt="$work/system/opt/io" link="$work/system/usr/local/bin/io"
sed -i '' -e "s|prefix=/opt/io link=/usr/local/bin/io|prefix=$opt link=$link|" \
    -e 's|EUID == 0|EUID != 0|' -e "s|-o root -g wheel|-o $uid -g $(id -g)|g" \
    "$project/scripts/install.sh"
mkdir -p "${link:h}"
ln -s /unrelated "$link"
check 1 'Conflicting symbolic link' "$project/scripts/install.sh"
[[ $(readlink "$link") == /unrelated && ! -e $opt ]] || fail 'conflict was changed'
rm "$link"
print 'unrelated executable' > "$link"
check 1 'Conflicting file' "$project/scripts/install.sh"
[[ $(< "$link") == 'unrelated executable' ]] || fail 'conflicting file changed'
rm "$link"
mkdir "$opt"
touch "$opt/unrelated"
check 1 'Unsafe system directory' "$project/scripts/install.sh"
[[ -f $opt/unrelated ]] || fail 'preexisting directory changed'
rm "$opt/unrelated"
rmdir "$opt"
rmdir "${opt:h}" "${link:h}" "${link:h:h}"
check 0 'Installed io 0.1.0' "$project/scripts/install.sh"
[[ $(readlink "$link") == "$opt/bin/io" && -x $link ]] || fail 'invalid installed link'
check 0 'Usage:' "$link" --help
touch "$opt/bin/unrelated"
check 1 'Unexpected entries' "$project/scripts/uninstall.sh"
[[ -f $opt/bin/unrelated && -L $link ]] || fail 'uninstall removed a conflicting file'
rm "$opt/bin/unrelated"
print 0.1.1 > "$project/VERSION"
check 0 'Installed io 0.1.1' "$project/scripts/install.sh"
[[ $(< "$opt/VERSION") == 0.1.1 ]] || fail 'upgrade did not replace version'
before=$(< "$apps")
check 0 'application files removed' "$project/scripts/uninstall.sh"
[[ ! -e $opt && ! -L $link && $(< "$apps") == "$before" && -f $cache ]] || fail 'uninstall scope'
check 0 'application files removed' "$project/scripts/uninstall.sh"
print 'All fixture checks passed.'
