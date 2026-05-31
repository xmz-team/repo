#!/bin/bash

# 由于 repo 已经升级为 发行版结构 ，此脚本现已被废弃，现用于扁平化兼容
# 由 new.update.sh 调用

# 生成索引文件
dpkg-scanpackages -m . /dev/null > Packages
xz -c Packages > Packages.xz
bzip2 -c Packages > Packages.bz2
gzip -c Packages > Packages.gz
zstd -c Packages > Packages.zst

# ./update_git.sh
