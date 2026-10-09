#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

# invoke insmod with all arguments we got
# and use a pathname, as insmod doesn't look in . by default

KERNEL_NAME=$(grubby --default-kernel | grep -oP '(?!\/boot\/vmlinuz-)\d.+')

TARGET_PATH=$(find /lib/modules/"$KERNEL_NAME"/kernel/drivers/net/ethernet -name realtek -type d)
if [ "$TARGET_PATH" = "" ]; then
	TARGET_PATH=$(find /lib/modules/"$KERNEL_NAME"/kernel/drivers/net -name realtek -type d)
fi
if [ "$TARGET_PATH" = "" ]; then
	TARGET_PATH=/lib/modules/"$KERNEL_NAME"/kernel/drivers/net
fi
echo
echo "Check old driver and unload it."
check=`lsmod | grep r8169`
if [ "$check" != "" ]; then
	echo "rmmod r8169"
	/sbin/rmmod r8169
fi

check=`lsmod | grep r8125`
if [ "$check" != "" ]; then
	echo "rmmod r8125"
	/sbin/rmmod r8125
fi

echo "Build the module and install"
echo "-------------------------------" >> log.txt
date 1>>log.txt
make clean
make LLVM=1 LD="ld.lld --strip-all -z now -z relro --enable-new-dtags --fat-lto-objects --lto-O3 -O 2" KCFLAGS+="-flto=full -O3 -m64 -march=native -fvisibility=hidden -ffat-lto-objects -fvirtual-function-elimination -fwhole-program-vtables -fstack-protector-strong -fstack-clash-protection -fcf-protection -mllvm -enable-pipeliner -fasynchronous-unwind-tables -fno-trapping-math -funified-lto -g0" $@ all 1>>log.txt || exit 1




module=`ls src/*.ko`
module=${module#src/}
module=${module%.ko}

if [ "$module" = "" ]; then
	echo "No driver exists!!!"
	exit 1
elif [ "$module" != "r8169" ]; then
	if test -e $TARGET_PATH/r8169.ko ; then
		echo "Backup r8169.ko"
		if test -e $TARGET_PATH/r8169.bak ; then
			i=0
			while test -e $TARGET_PATH/r8169.bak$i
			do
				i=$(($i+1))
			done
			echo "rename r8169.ko to r8169.bak$i"
			mv $TARGET_PATH/r8169.ko $TARGET_PATH/r8169.bak$i
		else
			echo "rename r8169.ko to r8169.bak"
			mv $TARGET_PATH/r8169.ko $TARGET_PATH/r8169.bak
		fi
	fi
	if test -e $TARGET_PATH/r8169.ko.zst ; then
		echo "Backup r8169.ko.zst"
		if test -e $TARGET_PATH/r8169.zst.bak ; then
			i=0
			while test -e $TARGET_PATH/r8169.zst.bak$i
			do
				i=$(($i+1))
			done
			echo "rename r8169.ko.zst to r8169.zst.bak$i"
			mv $TARGET_PATH/r8169.ko.zst $TARGET_PATH/r8169.zst.bak$i
		else
			echo "rename r8169.ko.zst to r8169.zst.bak"
			mv $TARGET_PATH/r8169.ko.zst $TARGET_PATH/r8169.zst.bak
		fi
	fi
fi

zstd -d --rm $TARGET_PATH/r8125.ko.zst
pesign --certificate 'CachyOS Secure Boot' -s  --in $TARGET_PATH/r8125.ko --out $TARGET_PATH/r8125.ko.signed
mv $TARGET_PATH/r8125.ko.signed $TARGET_PATH/r8125.ko

echo "DEPMOD "$KERNEL_NAME""
depmod "$KERNEL_NAME"
echo "load module $module"
modprobe $module

is_update_initramfs=n
distrib_list="ubuntu debian"

if [ -r /etc/debian_version ]; then
	is_update_initramfs=y
elif [ -r /etc/lsb-release ]; then
	for distrib in $distrib_list
	do
		/bin/grep -i "$distrib" /etc/lsb-release 2>&1 /dev/null && \
			is_update_initramfs=y && break
	done
fi

if [ "$is_update_initramfs" = "y" ]; then
	if which update-initramfs >/dev/null ; then
		echo "Updating initramfs. Please wait."
		update-initramfs -u -k $(uname -r)
	else
		echo "update-initramfs: command not found"
		exit 1
	fi
fi

echo "Completed."
exit 0
