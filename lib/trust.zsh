# Caller supplies a canonical absolute path to an existing item.
# Reject ACLs as well as group/other write permissions, since ACLs can grant write access independently.
trusted_path() {
    local item=$1 metadata details mode
    while true; do
        [[ ! -L $item ]] || return 1
        metadata=$(/usr/bin/stat -f '%u %OLp' "$item") || return 1
        [[ $metadata == '0 '* ]] || return 1
        mode=${metadata#* }
        (( (8#$mode & 8#22) == 0 )) || return 1
        details=$(/bin/ls -lde "$item") || return 1
        [[ $details != *$'\n'* ]] || return 1
        [[ $item == / ]] && return 0
        item=${item:h}
    done
}
