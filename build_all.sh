#!/bin/bash 


# 参数说明
# ./build_all.sh  $1 $2 $3 $4 $5 $6 $7
# 比如 ./build_all.sh c_u  c_k5  c_rtfs c_rtfs_img c_sys_img cp_ko ==> 某个参数不需要时 可以用"-"代替
# $1 ==> 为 c_u 表明 要编译uboot, 其他的值表示不需要编译uboot 
# $2 ==> 为 c_k5 表示用kernel 5的内核版本 
#        为 c_k4 表示用kernel 4的内核版本 
#        为 其他的值表示不编译内核 
# $3 ==> 为 c_rtfs 表示需要重新下载与制作debian文件系统，为其他的值表明不用重新下载与制作debian文件系统【这个做了一遍后，后面就可以跳过了，太费时，用已有的就好了】
# $4 ==> 为 c_rtfs_img 【注意这个是文件系统镜像，不是整个系统的镜像】  表示需要生成镜像linaro-rootfs.img  ，为其他的值表明不用重新生成镜像linaro-rootfs.img  
# $5 ==> 为 c_sys_img  表示需要系统镜像，为其他的值表明不用生成系统镜像
# $6 ==> 为 cp_ko  表示要去拷贝我的调试ko 到文件系统里面去  ，为其他的值表明不用拷贝我的调试ko 到文件系统里面去 
# $7 ==> 为 c_qu: 因为为了调通qemu，uboot改了不少东西，其中还会uboot的启动命令这些，所以要区分对待了
#        为 c_bd: uboot编译使用master分支，保证编译出来的东西, rockpi4b物理单板上能正常启动 
# Exit the script if an error happens

# set -eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set -eE # Exit the script if an error happens

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

LOCALPATH=$(pwd)

TOPDIR=${LOCALPATH}/..

RELEASE=buster

CRT_UBOOT=$1
KERNEL_V=$2
ROOTFS_BUILD=$3
CRT_IMG=$4
CRT_SYS_IMG=$5
CPY_MY_KO=$6
COMPILE_TARGET=$7

export KERNEL_V

finish() {
	# 判断是是否kernel 4.x 还是 5.x 的内核版本
	if [ "${KERNEL_V}" == "c_k4" ]; then
		echo "resume env after compile kernel 4 ...."
		mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_4
		mv ${TOPDIR}/kernel_5_10_149 ${TOPDIR}/kernel
		echo "resume env for kernel 4 used done ...."	
	elif [ "${KERNEL_V}" == "c_k5" ]; then
		echo "resume env after compile kernel 5 ...."
	else
		echo "not compile kernel...."
	fi
	echo -e "\e[31m build all failed.\e[0m"
	exit -1
}
trap finish ERR HUP INT QUIT TERM

# 判断是是否kernel 4.x 还是 5.x 的内核版本
if [ "${KERNEL_V}" == "c_k4" ]; then
	echo "using kernel 4 ...."
	mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_5_10_149
	mv ${TOPDIR}/kernel_4  ${TOPDIR}/kernel
elif [ "${KERNEL_V}" == "c_k5" ]; then
	echo "using kernel 5 ...."
else
	echo "not compile kernel...."
fi

cd ${TOPDIR}

if [ "${CRT_UBOOT}" == "c_u" ]; then

	if [ "${COMPILE_TARGET}" == "" ]; then
		COMPILE_TARGET="c_qu"
	fi

	if [ "${COMPILE_TARGET}" == "c_qu" ]; then
		echo "compile for qemu ...."
		COMPILE_TARGET_QEMM="yes"
		cd ${TOPDIR}/u-boot 
		branch_exist=$(git branch  | grep  "rockllee" -w)
		if [ "${branch_exist}" == "" ]; then
			echo "git checkout -b rockllee  origin/rockllee"
			git checkout -b rockllee  origin/rockllee
		else
			cur_br=$(git branch  | grep  "* rockllee" -w)
			if ["${cur_br}" == ""]; then
				echo "git checkout rockllee"
				git checkout rockllee
			fi
		fi
	elif [ "${COMPILE_TARGET}" == "c_bd" ]; then
		echo "compile for rockpi4b board ...."
		branch_exist=$(git branch  | grep  "rockllee_rockpi4b" -w)
		if [ "${branch_exist}" == "" ]; then
			echo "git checkout -b rockllee_rockpi4b  origin/rockllee_rockpi4b"
			git checkout -b rockllee_rockpi4b  origin/rockllee_rockpi4b
		else
			cur_br=$(git branch  | grep  "* rockllee_rockpi4b" -w)
			if [ "${cur_br}" == "" ]; then
				echo "git checkout rockllee_rockpi4b"
				git checkout rockllee_rockpi4b
			fi
		fi
	else
		echo -e "\e[31m param err!.\e[0m"
		exit -1
	fi

	cd ${TOPDIR}
	./build/mk-uboot.sh rockpi4b
	echo -e "\e[32m build uboot done ...\e[0m"
else
	echo -e "\e[32m skip build uboot ...\e[0m"
fi

if [ "${KERNEL_V}" == "c_k5" ] || [ "${KERNEL_V}" == "c_k4" ]; then 
	./build/mk-kernel.sh rockpi4b
	echo -e "\e[32m build kernel done ...\e[0m"
else
	echo -e "\e[32m skip build kernel ...\e[0m"
fi

# set +eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set +eE # +e ==> donot Exit the script if an error happens
trap ''  ERR HUP INT QUIT TERM #因为文件系统处理过程中可能有依赖异常，所以临时要忽略错误退出 与 异常信号捕获的相关处理，后面再恢复即可
if [ "${ROOTFS_BUILD}" == "c_rtfs" ]; then
	cd ${TOPDIR}/rootfs
	export ARCH=arm64
	echo step-----111
	sudo apt-get install binfmt-support qemu-user-static gdisk
	echo step-----222
	# dpkg -i 是用来安装后面跟的软件包用的
	# 官方的注释如下右侧，让忽略 各个失败的依赖项
	# ubuntu-build-service/packages/* 下面有4个deb文件，是github库上自带的
	sudo dpkg -i ubuntu-build-service/packages/*        # ignore the broken dependencies, we will fix it next step
	echo step-----333
	sudo apt-get install -f
	# 配置 构建 出debian文件系统的目录结构以及各个文件下对应的二进制bin文件
	RELEASE=buster TARGET=desktop ARCH=${ARCH} ./mk-base-debian.sh
	echo step-----444
	# 基于上面debian的镜像，然后在这个文件系统挂的基础上 下载更新安装一些软件
	# ./mk-rootfs-buster.sh ==> 在 $TARGET_ROOTFS_DIR(~/rock_space/rockpi_4b/rockchip-bsp/rootfs/binary) 下制作文件系统的各个目录与准备软件
	# ./mk-image.sh ==> 就是把TARGET_ROOTFS_DIR 这个目录下的文件系统 通过 mkfs.ext4  生成文件系统镜像 linaro-rootfs.img 
	# 所以我们自己的软件可以在 ./mk-image.sh 这个脚本里面添加 或者 ./mk-rootfs-buster.sh 里面添加，我决定在 ./mk-image.sh 中添加 
	# 同时我决定把原来的两句话拆分成两部：VERSION=debug ARCH=${ARCH} ./mk-rootfs-buster.sh  && ./mk-image.sh  ==> 如下
	#     VERSION=debug ARCH=${ARCH} ./mk-rootfs-buster.sh  
	#     VERSION=debug ARCH=${ARCH} ./mk-image.sh
	# 这样不用每次都去下载机制基础的文件系统，太费事了
	VERSION=debug ARCH=${ARCH} ./mk-rootfs-buster.sh  && ./mk-image.sh
	echo -e "\e[32m  rootfs buster done  ...\e[0m"
	echo step-----555
else
	echo -e "\e[32m  skip create rootfs buster  ...\e[0m"
fi

if [ "${CPY_MY_KO}" == "cp_ko" ]; then
	${TOPDIR}/build/copy_my_ko.sh
	echo -e "\e[32m  copy my debug ko to rootfs done  ...\e[0m"
else
	echo -e "\e[32m  shipping copy my debug ko to rootfs done  ...\e[0m"
fi

if [ "${CRT_IMG}" == "c_rtfs_img" ]; then
	cd ${TOPDIR}/rootfs
	VERSION=debug ARCH=${ARCH} ./mk-image.sh
	echo -e "\e[32m  create rootfs img(linaro-rootfs.img) done  ...\e[0m"
else
	echo -e "\e[32m  skip create rootfs img(linaro-rootfs.img)  ...\e[0m"
fi

# set -eE #-E 设定之后 ERR 陷阱会被 shell 函数继承
set -eE # Exit the script if an error happens
trap finish ERR HUP INT QUIT TERM

if [ "${CRT_SYS_IMG}" == "c_sys_img" ]; then
	cd ${TOPDIR}
	echo step-----666
	# Generate system image with two partitions
	build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img
	echo step-----777
	# Generate ROCK Pi 4 system image with five partitions.
	# build/mk-image.sh -c rk3399 -t system -r rootfs/linaro-rootfs.img
fi

# 判断是是否kernel 4.x 还是 5.x 的内核版本
if [ "${KERNEL_V}" == "c_k4" ]; then
	echo "resume env after compile kernel 4 ...."
	mv ${TOPDIR}/kernel  ${TOPDIR}/kernel_4
	mv ${TOPDIR}/kernel_5_10_149 ${TOPDIR}/kernel  		
elif [ "${KERNEL_V}" == "c_k5" ]; then
	echo "resume env after compile kernel 5 ...."
else
	echo "not compile kernel...."
fi
	
echo -e "\e[36m all READY! ==> build_all ok\e[0m"
