#!/bin/bash

# Author: Anton Nefedenkov
# Do whatever you want with this
# Credit goes to Nick Miller and his blog post.
# Please read it: "Fast linux kernel testing with qemu"
# http://ncmiller.github.io/2016/05/14/linux-and-qemu.html
# IMPORTANT: This script assumes that it is run on Ubuntu


init () {
	if [ -z "$1" ]
	  then
	    echo "Need the name for dev directory"
	    exit 0
	fi

	# Install the dependencies
	sudo apt install ncurses-dev build-essential libssl-dev libelf-dev
	sudo apt install git
	sudo apt install qemu
	sudo apt install flex bison

	# Create a directory to host all the kernel dev under home
	mkdir -p $1
	TOP=$1
	cd $TOP

	# We need to download busybox. Busybox brings small versions of common
	# unix utilities together into one executable. Things like `ls` are not
	# part of the kernel, but what system can go by without `ls`? 
	wget http://busybox.net/downloads/busybox-1.24.2.tar.bz2 || exit 1
	tar xvf busybox-1.24.2.tar.bz2 || exit 1
	rm busybox-1.24.2.tar.bz2 || exit 1

	# We ofc need the linux kernel :)
	#git clone https://github.com/torvalds/linux.git

	# Default configure the busybox
	cd $TOP/busybox-1.24.2 || exit 1
	mkdir -p $TOP/build/busybox-x86 || exit 1
	make O=$TOP/build/busybox-x86 defconfig || exit 1

	# Configure busybox to build  as a static binary.
	# -> Busybox Setting -> Build options -> Build BusyBox as a static binary (no shared libs)
	# In the script we just append to the config file directly
	echo "CONFIG_STATIC=y" >> $TOP/build/busybox-x86/.config || exit 1

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
	   | gzip -9 > $TOP/build/initramfs-busybox-x86.cpio.gz;

}

if [ -z "$1" ]
  then
    echo "Need the path to top directory"
    exit 0
fi

if [ -z "$2" ]
  then
    echo "Need the command name"
    exit 0
fi

case $2 in
	init)
		init $1
		;;
	*)
		echo $"Usage: $0 {init|get_linux}"
		exit 1
esac
