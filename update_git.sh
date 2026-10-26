#!/bin/sh -

if [ ! -d ".git-upload" ]; then
    echo "[Error]: directory '.git-upload' does not exist" >&2
    exit 1
elif [ ! -f ".git-upload/instructions.ini" ]; then
    echo "[Eeror]: file '.git-upload/instructions.ini' does not exist" >&2
    exit 1
fi

source ".git-upload/instructions.ini"
export text="$instructions"

git add .
git diff --staged --quiet || git commit -m "updated by the update script $text $(date -u +'%Y-%m-%dT%H:%M:%SZ')"

git pull --rebase
git push origin main
