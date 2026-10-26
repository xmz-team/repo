#!/bin/bash

# It has been abandoned. Please do not use this script but use the new.update.sh script
# {
: '
# Generate index files
dpkg-scanpackages -m . /dev/null > Packages
xz -c Packages > Packages.xz
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.gz
zstd -c Packages > Packages.zst

# Calculate the check value
#### pkg
md5_pkg=$(md5sum Packages | cut -d' ' -f1)
size_pkg=$(wc -c < Packages)
#### xz
md5_xz=$(md5sum Packages.xz | cut -d' ' -f1)
size_xz=$(wc -c < Packages.xz)
#### bz2
md5_bz2=$(md5sum Packages.bz2 | cut -d' ' -f1)
size_bz2=$(wc -c < Packages.bz2)
#### zst
md5_zst=$(md5sum Packages.zst | cut -d' ' -f1)
size_zst=$(wc -c < Packages.zst)

./mkgpg

# Submit updates
git add .
git commit -m "Auto-update $(date +'%Y-%m-%d %H:%M')"
git pull --rebase
git push origin main
'
# }
echo "[Warn]: You are using a maintenance script that has been deprecated! For security reasons, we have automatically switched to the new maintenance script"
exec ./new.update.sh
