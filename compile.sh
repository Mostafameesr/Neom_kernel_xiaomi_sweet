#!/bin/bash
# =======================================================
#  FRANXXCORE ULTIMATE BUILDER SCRIPT
#  Mode: Notify via Script, Upload via YAML
# =======================================================

# --- CONFIGURATION ---
PHONE="Sweet"
CODENAME="ThriceUponATime"
DEFCONFIG="sweet_defconfig"
COMPILERDIR="$(pwd)/../aosp-clang"
CLANG_VER="r547379"

# Config Telegram (Diambil dari Environment YAML)
BOT_TOKEN="${TG_TOKEN}"
CHAT_ID="${TG_CHAT_ID}"
NAME_KERNEL="${NAME_KERNEL:-FranxxCORE}"

# Environment
export KBUILD_BUILD_USER="Rapli"
export KBUILD_BUILD_HOST="NyarchLinux"
export PATH="$COMPILERDIR/bin:$PATH"

# Colors
GRn="\033[92m"
REd="\033[91m"
BLu="\033[94m"
YLw="\033[93m"
NC="\033[0m"

# Buat folder penampungan untuk YAML
mkdir -p final_zips

# --- TELEGRAM FUNCTION (Text Only) ---
tg_send_msg() {
    # Cek jika Token ada, baru kirim
    if [ ! -z "$BOT_TOKEN" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d "parse_mode=HTML" \
            -d text="$1" > /dev/null
    fi
}

# ================= CORE FUNCTIONS =================

setup_clang() {
    echo -e "$BLu[+] Setting up Compiler...$NC"
    if [ ! -d "$COMPILERDIR" ]; then
        mkdir -p "$COMPILERDIR"
        wget -q --show-progress "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-${CLANG_VER}.tar.gz" -O "aosp-clang.tar.gz"
        tar -xf aosp-clang.tar.gz -C "$COMPILERDIR"
        rm -f aosp-clang.tar.gz
    fi
}

compile_kernel() {
    VARIANT=$1
    DATE_TAG=$(date '+%Y%m%d-%H%M')
    ZIPNAME="${NAME_KERNEL}-${VARIANT}-${CODENAME}-${DATE_TAG}.zip"

    echo -e "\n$GRn==========================================$NC"
    echo -e "$GRn    BUILDING: $VARIANT EDITION $NC"
    echo -e "$GRn==========================================$NC"

    # [NOTIFIKASI] Mulai Build
    MSG="<b>🔨 Build Started!</b>%0A%0A"
    MSG+="<b>Device:</b> $PHONE%0A"
    MSG+="<b>Variant:</b> $VARIANT%0A"
    MSG+="<b>Time:</b> $(date)"
    tg_send_msg "$MSG"

    # Clean DTB/DTBO Cache (PENTING UNTUK PATCH)
    rm -rf out/arch/arm64/boot/dts
    rm -f out/arch/arm64/boot/dtbo.img out/arch/arm64/boot/dtb.img

    # Start Compile
    make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
        CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        Image.gz dtbo.img dtb.img

    if [ -f "out/arch/arm64/boot/Image.gz" ]; then
        echo -e "$GRn[+] Build Success! Zipping...$NC"

        if [ ! -d "AnyKernel3" ]; then
            git clone -q https://github.com/RapliVx/AnyKernel3.git -b sweet AnyKernel3
        fi
        
        cp out/arch/arm64/boot/Image.gz AnyKernel3/
        cp out/arch/arm64/boot/dtb.img AnyKernel3/
        cp out/arch/arm64/boot/dtbo.img AnyKernel3/
        
        cd AnyKernel3
        git checkout sweet &> /dev/null
        zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
        cd ..

        # PINDAHKAN ZIP KE FOLDER FINAL (Agar bisa dipickup YAML)
        mv "$ZIPNAME" final_zips/
        echo -e "$GRn[+] File moved to final_zips/$ZIPNAME $NC"
        
        # Kita TIDAK kirim notif sukses disini, biarkan YAML yang kirim file release.
    else
        echo -e "$REd[!] Build Failed for $VARIANT!$NC"
        
        # [NOTIFIKASI] Gagal Build (Langsung lapor, gak perlu nunggu YAML)
        ERR_MSG="<b>❌ Build Failed!</b>%0A%0A"
        ERR_MSG+="<b>Variant:</b> $VARIANT%0A"
        ERR_MSG+="<i>Check GitHub Actions logs for details.</i>"
        tg_send_msg "$ERR_MSG"
    fi
}

# ================= EXECUTION FLOW =================

setup_clang
mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

# 1. AOSP BUILD
compile_kernel "AOSP"

# 2. MIUI PATCH & BUILD
echo -e "\n$YLw[+] Applying MIUI Patch...$NC"
TARGET_FILES=("dsi-panel-k6-38-0c-0a-fhd-dsc-video.dtsi" "dsi-panel-k6-38-0e-0b-fhd-dsc-video.dtsi")

for TARGET in "${TARGET_FILES[@]}"; do
    FILE_PATH=$(find . -type f -name "$TARGET" | head -n 1)
    if [ -n "$FILE_PATH" ]; then
        sed -i 's/qcom,mdss-pan-physical-width-dimension = <69>;/qcom,mdss-pan-physical-width-dimension = <695>;/g' "$FILE_PATH"
        sed -i 's/qcom,mdss-pan-physical-height-dimension = <154>;/qcom,mdss-pan-physical-height-dimension = <1546>;/g' "$FILE_PATH"
        echo -e "$GRn[OK] Patched: $FILE_PATH$NC"
    fi
done

compile_kernel "MIUI"

rm -rf AnyKernel3
echo -e "$GRn[+] All Done. Files are in 'final_zips/' folder.$NC"
