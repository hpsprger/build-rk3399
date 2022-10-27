#!/bin/bash 

set -e # Exit the script if an error happens

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

LOCALPATH=$(pwd)

TOPDIR=${LOCALPATH}/..

ROOTFS_BUILD=$1
RELEASE=buster

finish() {
	echo -e "\e[31m build all failed.\e[0m"
	exit -1
}
trap finish ERR

cd ${TOPDIR}

./build/mk-uboot.sh rockpi4b
echo -e "\e[32m build uboot done ...\e[0m"

./build/mk-kernel.sh rockpi4b
echo -e "\e[32m build kernel done ...\e[0m"

set +e
if [ $ROOTFS_BUILD ];  then
	cd ${TOPDIR}/rootfs
	export ARCH=arm64
	sudo apt-get install binfmt-support qemu-user-static gdisk
	sudo dpkg -i ubuntu-build-service/packages/*        # ignore the broken dependencies, we will fix it next step
	sudo apt-get install -f
	RELEASE=buster TARGET=desktop ARCH=${ARCH} ./mk-base-debian.sh
	VERSION=debug ARCH=${ARCH} ./mk-rootfs-buster.sh  && ./mk-image.sh
	echo -e "\e[32m  rootfs done  ...\e[0m"
else
	echo -e "\e[32m  rootfs already ok  ...\e[0m"
fi
set -e

cd ${TOPDIR}
# Generate system image with two partitions
build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img

# Generate ROCK Pi 4 system image with five partitions.
# build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img

echo -e "\e[36m all READY! \e[0m"
