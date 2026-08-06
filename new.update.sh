#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[1/5] Clear env..."
find pool -type d \( -name "DEBIAN" -o -name "var" -o -name "usr" -o -name "bin" -o -name "share" -o -name "etc" \) \
    -not -path "*/.git/*" \
    -exec rm -rf {} + 2>/dev/null || true

rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.zst

mkdir -p dists/AD/main/binary-all
mkdir -p dists/AD/main/binary-iphoneos-arm
mkdir -p dists/AD/main/binary-iphoneos-arm64
mkdir -p dists/AD/main/binary-iphoneos-arm64e
mkdir -p dists/AD/dev/binary-all
mkdir -p dists/AD/dev/binary-iphoneos-arm
mkdir -p dists/AD/dev/binary-iphoneos-arm64
mkdir -p dists/AD/dev/binary-iphoneos-arm64e

echo "[2/5] Generate Packages file..."

declare -A ARCH_POOL_MAP
ARCH_POOL_MAP["all"]="pool/main/all pool/dev/all"
ARCH_POOL_MAP["iphoneos-arm"]="pool/main/arm pool/dev/arm pool/lfjb/binary-iphoneos-arm"
ARCH_POOL_MAP["iphoneos-arm64"]="pool/main/arm64 pool/dev/arm64 pool/lfjb/binary-iphoneos-arm64"
ARCH_POOL_MAP["iphoneos-arm64e"]="pool/main/arm64e pool/dev/arm64e pool/lfjb/binary-iphoneos-arm64e"

COMPONENTS=("main" "dev")

for component in "${COMPONENTS[@]}"; do
    for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
        output_dir="dists/AD/${component}/binary-${arch}"
        output_file="${output_dir}/Packages"
        echo "  handle: ${component}/${arch}"
        pool_paths=""
        case "$component" in
            main)
                case "$arch" in
                    all) pool_paths="pool/main/all" ;;
                    iphoneos-arm) pool_paths="pool/main/arm" ;;
                    iphoneos-arm64) pool_paths="pool/main/arm64 pool/lfjb/binary-iphoneos-arm64" ;;
                    iphoneos-arm64e) pool_paths="pool/main/arm64e pool/lfjb/binary-iphoneos-arm64e" ;;
                esac
                ;;
            dev)
                case "$arch" in
                    all) pool_paths="pool/dev/all" ;;
                    iphoneos-arm) pool_paths="pool/dev/arm" ;;
                    iphoneos-arm64) pool_paths="pool/dev/arm64" ;;
                    iphoneos-arm64e) pool_paths="pool/dev/arm64e" ;;
                esac
                ;;
        esac
        has_debs=false
        for pp in $pool_paths; do
            if [ -d "$pp" ] && [ -n "$(find "$pp" -name "*.deb" -type f 2>/dev/null)" ]; then
                has_debs=true
                break
            fi
        done
        if [ "$has_debs" = true ]; then
            temp_pool=$(mktemp -d)
            for pp in $pool_paths; do
                if [ -d "$pp" ]; then
                    cp -r "$pp"/* "$temp_pool"/ 2>/dev/null || true
                fi
            done
            dpkg-scanpackages -m "$temp_pool" /dev/null 2>/dev/null > "$output_file"
	    echo "$(cat template/10086.template)" >> "$output_file"
            rm -rf "$temp_pool"
        else
            > "$output_file"
        fi
        if [ -s "$output_file" ]; then
            gzip -9c "$output_file" > "${output_file}.gz"
            bzip2 -9c "$output_file" > "${output_file}.bz2"
            xz -9c "$output_file" > "${output_file}.xz"
            zstd -19 -c "$output_file" > "${output_file}.zst"
        else
            rm -f "${output_file}.gz" "${output_file}.bz2" "${output_file}.xz" "${output_file}.zst"
        fi
    done
done

echo "[3/5] Generate Contents file..."

for component in "${COMPONENTS[@]}"; do
    for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
        output_dir="dists/AD/${component}/binary-${arch}"
        contents_file="${output_dir}/Contents-${arch}"
        packages_file="${output_dir}/Packages"
        if [ -s "$packages_file" ]; then
            echo "  Generate Contents: ${component}/${arch}"
            > "$contents_file"
            current_package=""
            current_filename=""
            while IFS= read -r line; do
                if [[ "$line" =~ ^Package:\ (.*) ]]; then
                    current_package="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^Filename:\ (.*) ]]; then
                    current_filename="${BASH_REMATCH[1]}"
                    if [ -n "$current_filename" ] && [ -f "$current_filename" ]; then
                        dpkg-deb -c "$current_filename" 2>/dev/null | while IFS= read -r fileline; do
                            file_path=$(echo "$fileline" | awk '{print $NF}' | sed 's/^\.//')
                            if [ -n "$file_path" ] && [ "$file_path" != "/" ]; then
                                echo "$file_path $current_package" >> "$contents_file"
                            fi
                        done
                    fi
                fi
            done < "$packages_file"
            if [ -s "$contents_file" ]; then
                sort -u "$contents_file" -o "$contents_file"
                gzip -9c "$contents_file" > "${contents_file}.gz"
                bzip2 -9c "$contents_file" > "${contents_file}.bz2"
                xz -9c "$contents_file" > "${contents_file}.xz"
                zstd -19 -c "$contents_file" > "${contents_file}.zst"
            fi
        fi
    done
done

echo "[4/5] Generate Release file..."

components_list=""
for component in "${COMPONENTS[@]}"; do
    has_packages=false
    for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
        if [ -s "dists/AD/${component}/binary-${arch}/Packages" ]; then
            has_packages=true
            break
        fi
    done
    if [ "$has_packages" = true ]; then
        components_list="$components_list $component"
    fi
done

components_list=$(echo "$components_list" | xargs)  # trim
arches_list=""

for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
    for component in $components_list; do
        if [ -s "dists/AD/${component}/binary-${arch}/Packages" ]; then
            arches_list="$arches_list $arch"
            break
        fi
    done
done

arches_list=$(echo "$arches_list" | xargs)
release_date=$(date -R)
release_file="dists/AD/Release"

cat > "$release_file" << EOF
Origin: XMZ-Team Repo
Label: XMZ-Team Repo
Suite: stable
Version: 1.0
Codename: AD
Date: $release_date
Architectures: $arches_list
Components: $components_list
Description: XMZ-Team Repo, Distribution of some essential tools for iPhoneOS
EOF

echo "MD5Sum:" >> "$release_file"

for component in $components_list; do
    for arch in $arches_list; do
        binary_dir="dists/AD/${component}/binary-${arch}"
        for file in "Packages" "Packages.gz" "Packages.bz2" "Packages.xz" "Packages.zst" \
                    "Contents-${arch}" "Contents-${arch}.gz" "Contents-${arch}.bz2" "Contents-${arch}.xz" "Contents-${arch}.zst"; do
            full_path="${binary_dir}/${file}"
            relative_path="${component}/binary-${arch}/${file}"
            if [ -f "$full_path" ]; then
                md5=$(md5sum "$full_path" | cut -d' ' -f1)
                size=$(wc -c < "$full_path")
                printf " %s %d %s\n" "$md5" "$size" "$relative_path" >> "$release_file"
            fi
        done
    done
done

echo "[5/5] Create a compatible symbolic link"
ln -sf dists/AD/Release Release 2>/dev/null || true

echo ""
echo "  Update done!"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"

./update_dpkg.sh
./update_git.sh

echo ""

