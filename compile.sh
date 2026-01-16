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

# Mengambil Config dari GitHub Actions Secrets/Env
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

# ================= TELEGRAM FUNCTIONS =================

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo -e "$REd[!] CRITICAL ERROR: Telegram Token or Chat ID is EMPTY!$NC"
fi

tg_send_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "parse_mode=HTML" \
        -d text="$1" > /dev/null
}

tg_send_file() {
    local file="$1"
    local caption="$2"
    echo -e "$BLu[+] Uploading file: $file ...$NC"
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F document=@"$file" \
        -F "parse_mode=HTML" \
        -F caption="$caption")
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d':' -f2)
    if [ "$HTTP_CODE" != "200" ]; then
        echo -e "$REd[!] UPLOAD FAILED! Telegram Response:$NC"
        echo "$RESPONSE"
        return 1
    else
        echo -e "$GRn[+] Upload Success!$NC"
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

    MSG="<b>🔨 New Build Triggered!</b>%0A%0A"
    MSG+="<b>Device:</b> <code>$PHONE</code>%0A"
    MSG+="<b>Variant:</b> <code>$VARIANT</code>%0A"
    MSG+="<b>Kernel:</b> <code>$NAME_KERNEL</code>%0A"
    tg_send_msg "$MSG"

    # --- [PENTING] CLEANUP DTB/DTBO LAMA ---
    # Ini yang akan membuat patch MIUI berefek.
    # Kita hapus cache DTB agar compiler dipaksa build ulang dtbo.img dengan angka baru.
    
    echo -e "$YLw[!] Cleaning old DTB/DTBO to force rebuild...$NC"
    rm -rf out/arch/arm64/boot/dts
    rm -f out/arch/arm64/boot/dtbo.img
    rm -f out/arch/arm64/boot/dtb.img

    # Start Compile
    make -j$(nproc --all) \
        O=out \
        ARCH=arm64 \
        LLVM=1 LLVM_IAS=1 \
        CC=clang \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        Image.gz dtbo.img dtb.img 2>&1 | tee "$LOG_FILE"

    if [ -f "out/arch/arm64/boot/Image.gz" ]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        MIN=$((DIFF / 60))
        SEC=$((DIFF % 60))

        echo -e "$GRn[+] Build Success! Zipping...$NC"

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

        FILESIZE=$(du -h "$ZIPNAME" | cut -f1)

        CAPTION="<b>✅ Build Success!</b>%0A%0A"
        CAPTION+="<b>📁 File:</b> <code>$ZIPNAME</code>%0A"
        CAPTION+="<b>⚡ Variant:</b> $VARIANT%0A"
        CAPTION+="<b>⏱ Duration:</b> ${MIN}m ${SEC}s%0A"
        CAPTION+="<b>📦 Size:</b> $FILESIZE%0A%0A"
        CAPTION+="<i>Enjoy your fresh kernel! Nihahahah</i> 😈"

        tg_send_file "$ZIPNAME" "$CAPTION"
        rm "$ZIPNAME"
    else
        echo -e "$REd[!] Build Failed for $VARIANT!$NC"
        ERROR_PREVIEW=$(tail -n 3 "$LOG_FILE")
        CAPTION="<b>❌ Build Failed!</b>%0A%0A"
        CAPTION+="<b>Variant:</b> $VARIANT%0A"
        CAPTION+="<b>Preview Error:</b>%0A<pre>$ERROR_PREVIEW</pre>"
        tg_send_file "$LOG_FILE" "$CAPTION"
        exit 1
    fi
}

# ================= EXECUTION FLOW =================

setup_clang
mkdir -p out

echo -e "$BLu[+] Generating Defconfig...$NC"
make O=out ARCH=arm64 $DEFCONFIG

# ---------------- PHASE 1: AOSP (CLEAN) ----------------
compile_kernel "AOSP"

# ---------------- PHASE 2: MIUI (PATCHED) ----------------
# Menggunakan Metode 'sed' karena 'patch' file sering gagal path
echo -e "\n$YLw[+] Starting Smart Patch for MIUI...$NC"

TARGET_FILES=(
    "dsi-panel-k6-38-0c-0a-fhd-dsc-video.dtsi"
    "dsi-panel-k6-38-0e-0b-fhd-dsc-video.dtsi"
)

for TARGET in "${TARGET_FILES[@]}"; do
    echo -e "$BLu[i] Searching for $TARGET...$NC"
    # Cari file dimanapun dia berada
    FILE_PATH=$(find . -type f -name "$TARGET" | head -n 1)

    if [ -n "$FILE_PATH" ]; then
        echo -e "$BLu[+] Found at: $FILE_PATH$NC"
        echo -e "$BLu[+] Applying MIUI dimensions (695/1546)...$NC"
        
        # Ubah angka 69 -> 695
        sed -i 's/qcom,mdss-pan-physical-width-dimension = <69>;/qcom,mdss-pan-physical-width-dimension = <695>;/g' "$FILE_PATH"
        # Ubah angka 154 -> 1546
        sed -i 's/qcom,mdss-pan-physical-height-dimension = <154>;/qcom,mdss-pan-physical-height-dimension = <1546>;/g' "$FILE_PATH"
        
        echo -e "$GRn[OK] Patched successfully.$NC"
    else
        echo -e "$REd[!] CRITICAL: File $TARGET NOT FOUND! Skip.$NC"
    fi
done

# Compile MIUI (Fungsi ini akan otomatis hapus DTBO lama dan rebuild ulang)
compile_kernel "MIUI"

# Cleanup Akhir
rm -rf AnyKernel3 build_log_*.txt
echo -e "$GRn[+] All Done.$NC"