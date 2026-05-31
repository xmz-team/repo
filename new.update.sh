#!/bin/bash
# 原 AD-iOS Repo 维护着: AD-iOS，现由 XMZ-Team 所有并且维护
# XMZ-Team Repo 的维护更新脚本

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# ============================================
# 1. 清理临时文件和解压目录
# ============================================
echo "[1/5] 清理环境..."

# 删除 pool 中的解压目录（可能是误解压的 deb 包）
find pool -type d \( -name "DEBIAN" -o -name "var" -o -name "usr" -o -name "bin" -o -name "share" -o -name "etc" \) \
    -not -path "*/.git/*" \
    -exec rm -rf {} + 2>/dev/null || true

# 清理根目录的临时 Packages 文件（会在 dists 中重新生成）
rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.zst

# 确保目录存在
mkdir -p dists/AD/main/binary-all
mkdir -p dists/AD/main/binary-iphoneos-arm
mkdir -p dists/AD/main/binary-iphoneos-arm64
mkdir -p dists/AD/main/binary-iphoneos-arm64e
mkdir -p dists/AD/dev/binary-all
mkdir -p dists/AD/dev/binary-iphoneos-arm
mkdir -p dists/AD/dev/binary-iphoneos-arm64
mkdir -p dists/AD/dev/binary-iphoneos-arm64e

# ============================================
# 2. 扫描并生成各架构的 Packages
# ============================================
echo "[2/5] 生成 Packages 文件..."

# 架构与 pool 子目录的映射关系
declare -A ARCH_POOL_MAP
ARCH_POOL_MAP["all"]="pool/main/all pool/dev/all"
ARCH_POOL_MAP["iphoneos-arm"]="pool/main/arm pool/dev/arm pool/lfjb/binary-iphoneos-arm"
ARCH_POOL_MAP["iphoneos-arm64"]="pool/main/arm64 pool/dev/arm64 pool/lfjb/binary-iphoneos-arm64"
ARCH_POOL_MAP["iphoneos-arm64e"]="pool/main/arm64e pool/dev/arm64e pool/lfjb/binary-iphoneos-arm64e"

# 组件列表
COMPONENTS=("main" "dev")

for component in "${COMPONENTS[@]}"; do
    for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
        output_dir="dists/AD/${component}/binary-${arch}"
        output_file="${output_dir}/Packages"
        
        echo "  处理: ${component}/${arch}"
        
        # 收集该组件该架构的 pool 路径
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
        
        # 检查 pool 路径是否存在且包含 .deb 文件
        has_debs=false
        for pp in $pool_paths; do
            if [ -d "$pp" ] && [ -n "$(find "$pp" -name "*.deb" -type f 2>/dev/null)" ]; then
                has_debs=true
                break
            fi
        done
        
        if [ "$has_debs" = true ]; then
            # 创建临时目录，合并多个 pool 路径
            temp_pool=$(mktemp -d)
            for pp in $pool_paths; do
                if [ -d "$pp" ]; then
                    cp -r "$pp"/* "$temp_pool"/ 2>/dev/null || true
                fi
            done
            
            # 生成 Packages（不包含 MD5，后续统一计算）
            dpkg-scanpackages -m "$temp_pool" /dev/null 2>/dev/null > "$output_file"
	    # 添加虚假 deb
	    echo "$(cat template/10086.template)" >> "$output_file"
            # 清理临时目录
            rm -rf "$temp_pool"
        else
            # 清空 Packages 文件
            > "$output_file"
        fi
        
        # 只生成非空的压缩版本
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

# ============================================
# 3. 生成 Contents 文件
# ============================================
echo "[3/5] 生成 Contents 文件..."

# Contents 文件映射包内文件到包名
for component in "${COMPONENTS[@]}"; do
    for arch in all iphoneos-arm iphoneos-arm64 iphoneos-arm64e; do
        output_dir="dists/AD/${component}/binary-${arch}"
        contents_file="${output_dir}/Contents-${arch}"
        packages_file="${output_dir}/Packages"
        
        if [ -s "$packages_file" ]; then
            echo "  生成 Contents: ${component}/${arch}"
            
            # 提取 Packages 中的包名和文件名
            > "$contents_file"
            
            # 解析 Packages 文件，获取每个包的路径
            current_package=""
            current_filename=""
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^Package:\ (.*) ]]; then
                    current_package="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^Filename:\ (.*) ]]; then
                    current_filename="${BASH_REMATCH[1]}"
                    
                    # 如果 deb 文件存在，列出其内容
                    if [ -n "$current_filename" ] && [ -f "$current_filename" ]; then
                        dpkg-deb -c "$current_filename" 2>/dev/null | while IFS= read -r fileline; do
                            # dpkg-deb -c 输出格式: drwxr-xr-x 0/0 0 2024-01-01 00:00 ./
                            # 提取文件名
                            file_path=$(echo "$fileline" | awk '{print $NF}' | sed 's/^\.//')
                            if [ -n "$file_path" ] && [ "$file_path" != "/" ]; then
                                echo "$file_path $current_package" >> "$contents_file"
                            fi
                        done
                    fi
                fi
            done < "$packages_file"
            
            # 排序去重
            if [ -s "$contents_file" ]; then
                sort -u "$contents_file" -o "$contents_file"
                
                # 生成压缩版本
                gzip -9c "$contents_file" > "${contents_file}.gz"
                bzip2 -9c "$contents_file" > "${contents_file}.bz2"
                xz -9c "$contents_file" > "${contents_file}.xz"
                zstd -19 -c "$contents_file" > "${contents_file}.zst"
            fi
        fi
    done
done

# ============================================
# 4. 生成 Release 文件
# ============================================
echo "[4/5] 生成 Release 文件..."

# 收集所有有效的 Components
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

# 收集实际使用的架构
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

# 获取当前时间（RFC 2822 格式）
release_date=$(date -R)

# 开始构建 Release 文件
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

# 计算 MD5 校验和
echo "MD5Sum:" >> "$release_file"

for component in $components_list; do
    for arch in $arches_list; do
        binary_dir="dists/AD/${component}/binary-${arch}"
        
        # Packages 及其压缩版本
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

# 创建根目录的 Release 符号链接
ln -sf dists/AD/Release Release 2>/dev/null || true
echo "[5/5] 更新子仓库...(已禁用)"
# {
: '
# ============================================
# 5. 更新其他子仓库
# ============================================
echo "[5/5] 更新子仓库..."

# 更新 repo/lfjb 目录
if [ -d "repo/lfjb" ]; then
    echo "  更新 repo/lfjb..."
    cd repo/lfjb
    
    # 如果 lfjb 有独立的 pool，这里处理
    if [ -d "../../pool/lfjb" ]; then
        for arch_dir in binary-iphoneos-arm binary-iphoneos-arm64 binary-iphoneos-arm64e; do
            if [ -d "../../pool/lfjb/$arch_dir" ]; then
                arch_name=$(echo "$arch_dir" | sed 's/binary-//')
                dpkg-scanpackages -m "../../pool/lfjb/$arch_dir" /dev/null 2>/dev/null > "Packages_${arch_name}" 2>/dev/null || true
            fi
        done
    fi
    
    # 合并所有架构的 Packages
    cat Packages_* > Packages 2>/dev/null || true
    rm -f Packages_*
    
    # 生成压缩版本
    if [ -s Packages ]; then
        gzip -9c Packages > Packages.gz
        bzip2 -9c Packages > Packages.bz2
        xz -9c Packages > Packages.xz
        zstd -19c Packages > Packages.zst
    fi
    
    cd "$REPO_ROOT"
fi
'
# }
# ============================================
# 完成
# ============================================
echo ""
echo "========================================="
echo "  更新完成！"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 可选：自动提交到 Git
# 取消下面的注释以启用自动提交
# read -p "是否提交到 Git? (y/N): " commit_git
# if [ "$commit_git" = "y" ] || [ "$commit_git" = "Y" ]; then
#     git add -A
#     git commit -m "Auto-update $(date '+%Y-%m-%d %H:%M:%S')"
#     git pull --rebase
#     git push origin main
#     echo "已提交到 Git"
# fi

# ============================================
./update_dpkg.sh
./update_git.sh
# ============================================

echo ""
