#!/bin/zsh -f
(( $# == 0 )) || { print -ru2 -- 'Usage: uninstall.sh'; exit 2; }
exec "${0:A:h}/install.sh" --uninstall
