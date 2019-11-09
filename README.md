# Learning Linux Kernel Development
The repo contains notes that I am taking while trying to learn the kernel.

## Setting up (VirtualBox + Ubuntu + QEMU)

My day job machine is a MBP, so I opted out for running a Ubuntu inside of Virtualbox.
I have abandonded efforts trying to compile the kernel on OSX, its much easier to just fire up a VM. 
After compiling the kernel on the VM, I am using QEMU inside of the VM to run the fresh kernel.
After spending considerable amount of time trying to set this up, I decided to write a script so I don't
need to repeat this feat. 
WARNING: Please note that my understanding of what I am doing is minimal, so use at your own risk.

```bash

# Downloads dependencies, builds busybox and sets up initramfs
# Some commands run with sudo (like installing stuff)
./scripts/setup.sh ~/kdev_folder_name init

# Basically git clone the kernel
./scripts/setup.sh ~/kdev_folder_name download_linux

# Defconfigs the kernel and builds it
./scripts/setup.sh ~/kdev_folder_name build_linux

# Now go into your dev folder
cd ~/kdev_folder_name

# Run QEMU
# -kernel <- where the kernel image
# -initrd <- the device that holds root filesystem
# -nographic <- no gui, just console
# -append <- connects the kernel console to our conseol or smth :) 
qemu-system-x86_64 \
  -kernel build/linux-x86-basic/arch/x86_64/boot/bzImage \
  -initrd build/initramfs-busybox-x86.cpio.gz \
  -nographic -append "console=ttyS0"
```

If all went great, you should be dropped into the fresh kernel shell. Busybox provides us
with basic utilities that we are all used to, so you should be able to execute the usual
commands.

## Links that helped me
### Basic Setup and building
http://ncmiller.github.io/2016/05/14/linux-and-qemu.html
http://blog.vmsplice.net/2011/02/near-instant-kernel-development-cycle.html
https://mgalgs.github.io/2015/05/16/how-to-build-a-custom-linux-kernel-for-qemu-2015-edition.html
