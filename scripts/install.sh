#!/bin/zsh -f
emulate -L zsh
setopt err_exit
export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
umask 022

readonly source_dir=${0:A:h:h}
readonly prefix=/opt/io link=/usr/local/bin/io
readonly maintenance_lock=${prefix:h}/.io-maintenance
readonly -a files=(VERSION LICENSE lib/trust.zsh bin/io)
readonly -a directories=(bin lib)
typeset stage=
typeset -i locked=0

message() {
    local fd=$1 color=$2 marker=$3
    shift 3
    if [[ -t $fd && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        printf '\033[1;%sm%s\033[0m %s\n' "$color" "$marker" "$*" >&$fd
    else
        print -ru "$fd" -- "$marker $*"
    fi
}
die() { message 2 31 '==> Error:' "$@"; exit 1; }
(( EUID == 0 )) || die "Run this script with sudo from a trusted copy of io."
[[ $# == 0 || ( $# == 1 && $1 == --uninstall ) ]] || die "Usage: install.sh [--uninstall]"
source "$source_dir/lib/trust.zsh"

# Refuse symlinked or writable system paths before creating or replacing anything.
require_directory() {
    [[ -d $1 && ! -L $1 && ${1:A} == "$1" ]] && trusted_path "$1" ||
        die "Unsafe system directory: $1"
}

make_directory() {
    if [[ ! -e $1 && ! -L $1 ]]; then
        /usr/bin/install -d -o root -g wheel -m 755 "$1"
    fi
    require_directory "$1"
}

check_link() {
    if [[ -L $link ]]; then
        [[ $(/usr/bin/readlink "$link") == "$prefix/bin/io" ]] ||
            die "Conflicting symbolic link: $link"
    elif [[ -e $link ]]; then
        die "Conflicting file: $link"
    fi
}

check_bundle() {
    require_directory "$prefix"
    local entry directory file
    local -a entries
    for directory in "${directories[@]}"; do
        require_directory "$prefix/$directory"
    done
    for file in "${files[@]}"; do
        entry=$prefix/$file
        [[ -f $entry && ! -L $entry ]] && trusted_path "$entry" ||
            die "Unexpected or missing io file: $entry"
    done
    entries=("$prefix"/*(DN))
    (( ${#entries} == 4 )) || die "Unexpected entries in $prefix."
    for directory in "${directories[@]}"; do
        entries=("$prefix/$directory"/*(DN))
        (( ${#entries} == 1 )) || die "Unexpected entries in $prefix/$directory."
    done
    /usr/bin/grep -Fxq '# io Installomator frontend' "$prefix/bin/io" ||
        die "Existing directory is not a recognized io installation: $prefix"
}

cleanup() {
    [[ -z $stage ]] || /bin/rm -rf -- "$stage"
    if (( locked )); then /bin/rmdir -- "$maintenance_lock"; fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_directory "${prefix:h:h}"
require_directory "${link:h:h:h}"
if [[ ${1:-} != --uninstall ]]; then
    make_directory "${prefix:h}"
fi
if [[ -e ${prefix:h} || -L ${prefix:h} ]]; then
    require_directory "${prefix:h}"
    /bin/mkdir -m 700 -- "$maintenance_lock" ||
        die "Another maintenance operation may be running: $maintenance_lock"
    locked=1
fi
for parent in "${link:h:h}" "${link:h}"; do
    if [[ -e $parent || -L $parent ]]; then require_directory "$parent"; fi
done
check_link
if [[ -e $prefix || -L $prefix ]]; then
    check_bundle
    upgrading=1
else
    upgrading=0
fi

if [[ ${1:-} == --uninstall ]]; then
    [[ ! -L $link ]] || /bin/rm -- "$link"
    if (( upgrading )); then
        for file in "${files[@]}"; do /bin/rm -- "$prefix/$file"; done
        for directory in "${directories[@]}"; do /bin/rmdir -- "$prefix/$directory"; done
        /bin/rmdir -- "$prefix"
    fi
    message 1 32 '==>' 'io application files removed. User configuration and cache preserved.'
    exit 0
fi

stage=$(/usr/bin/mktemp -d "${prefix:h}/.io-stage.XXXXXXXX")
make_directory "$stage/io"
for directory in "${directories[@]}"; do make_directory "$stage/io/$directory"; done
for file in "${files[@]}"; do
    [[ -f $source_dir/$file && ! -L $source_dir/$file ]] || die "Missing source file: $file"
    mode=644
    [[ $file != bin/io ]] || mode=755
    /usr/bin/install -o root -g wheel -m "$mode" "$source_dir/$file" "$stage/io/$file"
done
/usr/bin/grep -Fxq '# io Installomator frontend' "$stage/io/bin/io" || die "Invalid source executable."
make_directory "${link:h:h}"
make_directory "${link:h}"
if (( upgrading )); then
    # Fully stage the new release before replacing individual files atomically.
    for file in "${files[@]}"; do /bin/mv -fh -- "$stage/io/$file" "$prefix/$file"; done
else
    /bin/mv -h -- "$stage/io" "$prefix"
fi
[[ -L $link ]] || /bin/ln -s -- "$prefix/bin/io" "$link"
IFS= read -r io_version < "$prefix/VERSION"
message 1 32 '==>' "Installed io $io_version at $prefix."
