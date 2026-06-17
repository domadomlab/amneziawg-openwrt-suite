#!/bin/bash

PKG_NAME="amneziawg-shuka-suite"
VERSION="4.0.2"
ARCH="aarch64_cortex-a53"
BUILD_DIR="/tmp/ipk_build"
TARGET_IPK="${PKG_NAME}_${VERSION}_${ARCH}.ipk"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building IPK: $TARGET_IPK"

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/data/usr/bin
mkdir -p $BUILD_DIR/data/usr/lib/lua/luci/controller
mkdir -p $BUILD_DIR/data/etc/init.d
mkdir -p $BUILD_DIR/data/etc/sing-box
mkdir -p $BUILD_DIR/data/etc/amneziawg
mkdir -p $BUILD_DIR/data/etc/config
mkdir -p $BUILD_DIR/control

# Copy binary and scripts
cp $SRC_DIR/amneziawg-go $SRC_DIR/awg-new $SRC_DIR/sing-box $SRC_DIR/shuka_manager.py $SRC_DIR/amneziawg-start.sh $SRC_DIR/amneziawg-stop.sh $SRC_DIR/amneziawg-health-check.sh $SRC_DIR/awg-watchdog.sh $SRC_DIR/amneziawg-dns.sh $SRC_DIR/amneziawg-rescue.sh $SRC_DIR/amneziawg-switch.sh $BUILD_DIR/data/usr/bin/

# Copy init scripts
cp $SRC_DIR/sing-box.init $BUILD_DIR/data/etc/init.d/sing-box
cp $SRC_DIR/amneziawg_init $BUILD_DIR/data/etc/init.d/amneziawg

# Copy templates and config
cp $SRC_DIR/config.json.template $BUILD_DIR/data/etc/sing-box/
cp $SRC_DIR/amneziawg_config.uci $BUILD_DIR/data/etc/config/amneziawg

# Copy LuCI controllers
cp $SRC_DIR/amneziawg.lua $SRC_DIR/shuka_hybrid.lua $BUILD_DIR/data/usr/lib/lua/luci/controller/

# Set permissions
chmod +x $BUILD_DIR/data/usr/bin/*
chmod +x $BUILD_DIR/data/etc/init.d/*

# Create control file
cat <<CTRL_EOF > $BUILD_DIR/control/control
Package: $PKG_NAME
Version: $VERSION
Depends: libc, kmod-tun, iptables, ip-full, python3, curl
Architecture: $ARCH
Maintainer: domadomlab
Description: AmneziaWG 2.0 & Shuka (Sing-box 1.13) Hybrid Suite with automated LuCI UI.
CTRL_EOF

# Create postinst
cat <<POST_EOF > $BUILD_DIR/control/postinst
#!/bin/sh
/etc/init.d/sing-box enable
/etc/init.d/amneziawg enable
/etc/init.d/rpcd restart
[ -f /lib/ld-musl-aarch64.so.1 ] && [ ! -f /lib/ld-linux-aarch64.so.1 ] && ln -s /lib/ld-musl-aarch64.so.1 /lib/ld-linux-aarch64.so.1
[ -f /etc/sing-box/config.json ] || cp /etc/sing-box/config.json.template /etc/sing-box/config.json
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
exit 0
POST_EOF
chmod +x $BUILD_DIR/control/postinst

# Create prerm
cat <<PRERM_EOF > $BUILD_DIR/control/prerm
#!/bin/sh
/etc/init.d/sing-box stop
/etc/init.d/sing-box disable
/etc/init.d/amneziawg stop
/etc/init.d/amneziawg disable
exit 0
PRERM_EOF
chmod +x $BUILD_DIR/control/prerm

echo "2.0" > $BUILD_DIR/debian-binary

cd $BUILD_DIR/control
tar --owner=0 --group=0 -czf ../control.tar.gz ./*
cd $BUILD_DIR/data
tar --owner=0 --group=0 -czf ../data.tar.gz ./*
cd $BUILD_DIR
tar --owner=0 --group=0 -czf $SRC_DIR/$TARGET_IPK debian-binary data.tar.gz control.tar.gz

echo "IPK built successfully: $SRC_DIR/$TARGET_IPK"
