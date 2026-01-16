#!/bin/bash
# =======================================================
#  FRANXXCORE ULTIMATE BUILDER SCRIPT
#  Support: Dual Build (AOSP & MIUI) + Smart Notification
#  Dev: RapliVx | Modified by Assistant
# =======================================================

# --- CONFIGURATION ---
PHONE="Sweet"
CODENAME="DoYouLoveMe"
DEFCONFIG="sweet_defconfig"
COMPILER_NAME="AOSP Clang"
CLANG_VER="r547379"
COMPILERDIR="$(pwd)/../aosp-clang"

# Telegram Config
BOT_TOKEN="${TG_TOKEN}"
CHAT_ID="${TG_CHAT_ID}"

# Patch Config
MIUI_PATCH_URL="https://raw.githubusercontent.com/RapliVx/personal_patch/refs/heads/main/miui_panel_sweet.patch"

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

# ================= TELEGRAM FUNCTIONS =================

# Fungsi kirim pesan HTML
tg_send_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "parse_mode=HTML" \
        -d text="$1" > /dev/null
}

# Fungsi kirim file dengan caption
tg_send_file() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F document=@"$1" \
        -F "parse_mode=HTML" \
        -F caption="$2" > /dev/null
}

# Fungsi Sticker (Opsional - Biar keren)
tg_send_sticker() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendSticker" \
        -d chat_id="$CHAT_ID" \
        -d sticker="$1" > /dev/null
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

# Fungsi Build Utama
compile_kernel() {
    VARIANT=$1
    START_TIME=$(date +%s)
    DATE_TAG=$(date '+%Y%m%d-%H%M')
    ZIPNAME="${NAME_KERNEL}-${VARIANT}-${CODENAME}-${DATE_TAG}.zip"
    LOG_FILE="build_log_${VARIANT}.txt"

    echo -e "\n$GRn==========================================$NC"
    echo -e "$GRn   BUILDING: $VARIANT EDITION $NC"
    echo -e "$GRn==========================================$NC"

    # Notifikasi Mulai
    MSG="<b>🔨 New Build Triggered!</b>%0A%0A"
    MSG+="<b>Device:</b> <code>$PHONE</code>%0A"
    MSG+="<b>Variant:</b> <code>$VARIANT</code>%0A"
    MSG+="<b>Date:</b> <code>$(date)</code>%0A"
    MSG+="<b>Compiler:</b> <code>$COMPILER_NAME</code>"
    tg_send_msg "$MSG"

    # Bersihkan sisa DTBO lama (Wajib untuk patch effect)
    rm -rf out/arch/arm64/boot/dts

    # Start Compile
    make -j$(nproc --all) \
        O=out \
        ARCH=arm64 \
        LLVM=1 LLVM_IAS=1 \
        CC=clang \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        Image.gz dtbo.img dtb.img 2>&1 | tee "$LOG_FILE"

    # Cek Keberhasilan
    if [ -f "out/arch/arm64/boot/Image.gz" ]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        MIN=$((DIFF / 60))
        SEC=$((DIFF % 60))

        echo -e "$GRn[+] Build Success! Zipping...$NC"

        # Siapkan AnyKernel3
        if [ ! -d "AnyKernel3" ]; then
            git clone -q https://github.com/RapliVx/AnyKernel3.git -b miatoll AnyKernel3
        fi
        
        cp out/arch/arm64/boot/Image.gz AnyKernel3/
        cp out/arch/arm64/boot/dtb.img AnyKernel3/
        cp out/arch/arm64/boot/dtbo.img AnyKernel3/
        
        cd AnyKernel3
        git checkout miatoll &> /dev/null
        zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
        cd ..

        # Ambil ukuran file
        FILESIZE=$(du -h "$ZIPNAME" | cut -f1)

        # Caption Sukses Keren
        CAPTION="<b>✅ Build Success!</b>%0A%0A"
        CAPTION+="<b>📁 File:</b> <code>$ZIPNAME</code>%0A"
        CAPTION+="<b>⚡ Variant:</b> $VARIANT%0A"
        CAPTION+="<b>⏱ Duration:</b> ${MIN}m ${SEC}s%0A"
        CAPTION+="<b>📦 Size:</b> $FILESIZE%0A%0A"
        CAPTION+="<i>Enjoy your fresh kernel! Nihahahah</i> 😈"

        tg_send_file "$ZIPNAME" "$CAPTION"
        
        # Hapus zip setelah upload hemat storage runner
        rm "$ZIPNAME"
    else
        echo -e "$REd[!] Build Failed for $VARIANT!$NC"
        
        # Ambil 5 baris terakhir error untuk preview
        ERROR_PREVIEW=$(tail -n 3 "$LOG_FILE")
        
        CAPTION="<b>❌ Build Failed!</b>%0A%0A"
        CAPTION+="<b>Variant:</b> $VARIANT%0A"
        CAPTION+="<b>Preview Error:</b>%0A<pre>$ERROR_PREVIEW</pre>%0A%0A"
        CAPTION+="<i>Check attached log for details.</i>"

        tg_send_file "$LOG_FILE" "$CAPTION"
        exit 1
    fi
}

# ================= EXECUTION FLOW =================

setup_clang
mkdir -p out

# Config Awal
echo -e "$BLu[+] Generating Defconfig...$NC"
make O=out ARCH=arm64 $DEFCONFIG

# ---------------- PHASE 1: AOSP ----------------
compile_kernel "AOSP"

# ---------------- PHASE 2: MIUI ----------------
echo -e "\n$YLw[+] Downloading Patch for MIUI...$NC"
wget -q "$MIUI_PATCH_URL" -O miui_panel.patch

echo -e "$YLw[+] Applying Patch...$NC"
if git apply --check miui_panel.patch 2>/dev/null; then
    git apply miui_panel.patch
    echo -e "$GRn[OK] Git Apply Success$NC"
else
    patch -p1 < miui_panel.patch
    echo -e "$GRn[OK] Standard Patch Success$NC"
fi

compile_kernel "MIUI"

# Cleanup Akhir
rm -rf AnyKernel3 miui_panel.patch build_log_*.txt
echo -e "$GRn[+] All Done.$NC"