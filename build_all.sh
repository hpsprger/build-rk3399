#!/bin/bash 


# ./build_all.sh            ==> 默认使用5.10的内核版本
# ./build_all.sh  k5        ==> 默认使用5.10的内核版本
# ./build_all.sh  k4 rootfs ==> 默认使用4.4的内核版本,  带上 rootfs 参数表示会重新制作 debian文件系统
# ./build_all.sh  k5 rootfs ==> 默认使用5.10的内核版本, 带上 rootfs 参数表示会重新制作 debian文件系统

# Exit the script if an error happens

# set -eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set -eE # Exit the script if an error happens

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

LOCALPATH=$(pwd)

TOPDIR=${LOCALPATH}/..

KERNEL_V=$1
ROOTFS_BUILD=$2
RELEASE=buster

export KERNEL_V

finish() {
	# 判断是是否kernel 4.x 还是 5.x 的内核版本
	if [ "${KERNEL_V}" == "k4" ]; then
		echo "resume env for kernel 4 used...."
		mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_4
		mv ${TOPDIR}/kernel_5_10_149 ${TOPDIR}/kernel
		echo "resume env for kernel 4 used done ...."	
	else
		echo "resume env for kernel 5 used...."
	fi
	echo -e "\e[31m build all failed.\e[0m"
	exit -1
}
trap finish ERR HUP INT QUIT TERM

# 判断是是否kernel 4.x 还是 5.x 的内核版本
if [ "${KERNEL_V}" == "k4" ]; then
	echo "using kernel 4 ...."
	mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_5_10_149
	mv ${TOPDIR}/kernel_4  ${TOPDIR}/kernel
else
	echo "using kernel 5 ...."
fi

cd ${TOPDIR}

./build/mk-uboot.sh rockpi4b
echo -e "\e[32m build uboot done ...\e[0m"

./build/mk-kernel.sh rockpi4b
echo -e "\e[32m build kernel done ...\e[0m"

# set +eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set +eE # +e ==> donot Exit the script if an error happens
trap ''  ERR HUP INT QUIT TERM #因为文件系统处理过程中可能有依赖异常，所以临时要忽略错误退出 与 异常信号捕获的相关处理，后面再恢复即可
if [ $ROOTFS_BUILD ];  then
	cd ${TOPDIR}/rootfs
	export ARCH=arm64
	echo step-----111
	sudo apt-get install binfmt-support qemu-user-static gdisk
	echo step-----222
	# dpkg -i 是用来安装后面跟的软件包用的
	# 官方的注释如下右侧，让忽略 各个失败的依赖项
	sudo dpkg -i ubuntu-build-service/packages/*        # ignore the broken dependencies, we will fix it next step
	echo step-----333
	sudo apt-get install -f
	RELEASE=buster TARGET=desktop ARCH=${ARCH} ./mk-base-debian.sh
	echo step-----444
	VERSION=debug ARCH=${ARCH} ./mk-rootfs-buster.sh  && ./mk-image.sh
	echo -e "\e[32m  rootfs done  ...\e[0m"
else
	echo -e "\e[32m  rootfs already ok  ...\e[0m"
fi
# set -eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set -eE # Exit the script if an error happens
trap finish ERR HUP INT QUIT TERM

cd ${TOPDIR}
# Generate system image with two partitions
build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img

# Generate ROCK Pi 4 system image with five partitions.
# build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img

# 判断是是否kernel 4.x 还是 5.x 的内核版本
if [ "${KERNEL_V}" == "k4" ]; then
	echo "resume env for kernel 4 used...."
	mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_4
	mv ${TOPDIR}/kernel_5_10_149 ${TOPDIR}/kernel  			
else
	echo "resume env for kernel 5 used...."
fi
	
echo -e "\e[36m all READY! \e[0m"
