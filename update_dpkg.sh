#!/bin/bash

# Because the repo has been upgraded to the distribution structure, this script has now been discarded and is now used for flattening compatibility.
# Called by new.update.sh

# Generate index files
dpkg-scanpackages -m . /dev/null > Packages
# {
# Add fake deb packages
orig_dir="$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)"
echo "$(cat ${orig_dir}/template/10086.template)" >> Packages
# }
xz -c Packages > Packages.xz
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.gz
zstd -c Packages > Packages.zst
