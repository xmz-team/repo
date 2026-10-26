#!/bin/bash

_root="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
if [ ! -d "${_root}/.git-upload" ]; then
    echo "[Error]: directory '.git-upload' does not exist" >&2
    exit 1
elif [ ! -f "${_root}/.git-upload/instructions.ini" ]; then
    echo "[Eeror]: file '.git-upload/instructions.ini' does not exist" >&2
    exit 1
fi

source "${_root}/.git-upload/instructions.ini"
export text="updated by the update script
${instructions}
$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

git add .
git diff --staged --quiet || git commit -m "${text}"
git pull --rebase
git push origin main
