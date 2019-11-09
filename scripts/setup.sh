# Author: Anton Nefedenkov
# Do whatever you want with this
# Credit goes to Nick Miller and his blog post.
# Please read it: "Fast linux kernel testing with qemu"
# http://ncmiller.github.io/2016/05/14/linux-and-qemu.html
# IMPORTANT: This script assumes that it is run on Ubuntu

# Install the dependencies
sudo apt install ncurses-dev build-essential libssl-dev libelf-dev
sudo apt install git
sudo apt install qemu
sudo apt install flex bison

# Create a directory to host all the kernel dev under home
cd $HOME
mkdir kdev
TOP=$HOME/kdev

# We need to download busybox. Busybox brings small versions of common
# unix utilities together into one executable. Things like `ls` are not
# part of the kernel, but what system can go by without `ls`? 
wget http://busybox.net/downloads/busybox-1.24.2.tar.bz2
tar xvf busybox-1.24.2.tar.bz2
rm busybox-1.24.2.tar.bz2

# We ofc need the linux kernel :)
#git clone https://github.com/torvalds/linux.git

# Default configure the busybox
cd $TOP/busybox-1.24.2
mkdir -p $TOP/build/busybox-x86
make O=$TOP/build/busybox-x86 defconfig

# Configure busybox to build  as a static binary.
# -> Busybox Setting -> Build options -> Build BusyBox as a static binary (no shared libs)
# Press <Y> to enable the setting
make O=$TOP/build/busybox-x86 menuconfig

# Build busybox
cd $TOP/build/busybox-x86
make -j2
make install

# Kernels need a filesystem to run. This is also where it finds init.
mkdir -p $TOP/build/initramfs/busybox-x86
cd $TOP/build/initramfs/busybox-x86
mkdir -pv {bin,sbin,etc,proc,sys,usr/{bin,sbin}}
cp -av $TOP/build/busybox-x86/_install/* .

# We need a init script that the kernel boots into
touch init
echo "#!/bin/sh
mount -t proc none /proc\n
mount -t sysfs none /sys\n
exec /bin/sh" > init

# Need it to be executable
chmod +x

# Generate initramfs, not sure how this works yet. Yay!
find . -print0 \
   | cpio --null -ov --format=newc \
   | gzip -9 > $TOP/build/initramfs-busybox-x86.cpio.gz







