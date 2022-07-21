#! /bin/bash
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2020, Roland Nagy <rnagy@xmimx.tk>

set -x


TARGETDIR="$1"
VIRTFS_AUTOMOUNT="$2"
VIRTFS_MOUNTPOINT="$3"
PSS_AUTOMOUNT="$4"

if [[ -z $TARGET_DIR ]]; then
    echo "TARGET_DIR missing"
    exit 1
fi

if [[ -z $VIRTFS_AUTOMOUNT ]]; then
    echo "VIRTFS_AUTOMOUNT missing"
    exit 1
fi

if [[ -z $VIRTFS_MOUNTPOINT ]]; then
    echo "VIRTFS_MOUNTPOINT missing"
    exit 1
fi

if [[ -z $PSS_AUTOMOUNT ]]; then
    echo "PSS_AUTOMOUNT missing"
    exit 1
fi


if [[ $VIRTFS_AUTOMOUNT == "y" ]]; then
    grep host "$TARGETDIR"/etc/fstab > /dev/null || \
    echo "host $VIRTFS_MOUNTPOINT 9p trans=virtio,version=9p2000.L,msize=65536,rw 0 0" >> "$TARGETDIR"/etc/fstab
    echo "[+] shared directory mount added to fstab"
fi

if [[ $PSS_AUTOMOUNT == "y" ]]; then
    mkdir -p "$TARGETDIR"/data/tee
    grep secure "$TARGETDIR"/etc/fstab > /dev/null || \
    echo "secure /data/tee 9p trans=virtio,version=9p2000.L,msize=65536,rw 0 0" >> "$TARGET_DIR"/etc/fstab
    echo "[+] persistent secure storage mount added to fstab"
fi

# from package optee_client_ext:
# # User tee is used to run tee-supplicant because access to /dev/teepriv0 is
# # restricted to group tee.
# # Any user in group teeclnt (such as test) may run client applications.
# # Any user in group ion may access /dev/ion
# define OPTEE_CLIENT_EXT_USERS
# 	tee -1 tee -1 * - /bin/sh - TEE user
# 	- -1 teeclnt -1 - - - - TEE users group
# 	- -1 ion -1 - - - - ION users group
# 	test -1 test -1 - - /bin/sh teeclnt,ion Test user, may run TEE client applications
# endef

if ! grep 'tee' "$TARGET_DIR"/etc/passwd; then
    # 1000 may be used by other users
    echo 'tee:x:1001:1001:TEE user:/:/bin/sh' >> "$TARGET_DIR"/etc/passwd
    echo 'test:x:1002:1004:Test user, may run TEE client applications:/:/bin/sh' >> "$TARGET_DIR"/etc/passwd

    echo 'tee:*:::::::' >> "$TARGET_DIR"/etc/shadow
    echo 'test::::::::' >> "$TARGET_DIR"/etc/shadow

    # 1000 may be used by other groups
    echo 'tee:x:1001:' >> "$TARGET_DIR"/etc/group
    echo 'test:x:1004:' >> "$TARGET_DIR"/etc/group
    echo 'teeclnt:x:1002:test' >> "$TARGET_DIR"/etc/group
    echo 'ion:x:1003:test' >> "$TARGET_DIR"/etc/group
fi

if ! grep 'proxy.sh' "$TARGETDIR"/etc/profile; then
    echo 'source /mnt/host/ai_tee/proxy.sh' >> "$TARGETDIR"/etc/profile
fi

# echo '
# export PYENV_ROOT="$HOME/.pyenv"
# command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
# eval "$(pyenv init -)"
# ' >> "$TARGETDIR"/etc/profile
