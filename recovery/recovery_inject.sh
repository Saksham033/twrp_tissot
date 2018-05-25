#!/bin/bash
#
#
DEVICE_RECOVERY_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET_RECOVERY_ROOT_OUT=$1


echo ""
echo "----------------------------------------------------------------"
echo "[#] Performing TWRP touch-ups and Treble Manager build..."

echo "    [#] Injecting recovery bootstrap service..."
sed -i 's/service recovery \/sbin\/recovery/service recovery \/sbin\/recovery\.sh/' "$TARGET_RECOVERY_ROOT_OUT/init.recovery.service.rc"

echo "    [#] Zipping Aroma resources (for Treble Manager gui)..."
rm "$TARGET_RECOVERY_ROOT_OUT/treble_manager/aroma_res.zip" > /dev/null 2>&1
cd "$DEVICE_RECOVERY_PATH/treble_manager_resources"
zip -rq -1 "$TARGET_RECOVERY_ROOT_OUT/treble_manager/aroma_res.zip" *
cd "$DEVICE_RECOVERY_PATH"

echo "[i] All done!"
echo "----------------------------------------------------------------"
echo ""