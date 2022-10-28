#!/bin/bash

# 很多基础的语法 与用法 请看mk-kernel.sh 脚本里面的注释

# 这个脚本的使用方法是 ./build/mk-uboot.sh rockpi4b 

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

LOCALPATH=$(pwd)
OUT=${LOCALPATH}/out
TOOLPATH=${LOCALPATH}/rkbin/tools
BOARD=$1

PATH=$PATH:$TOOLPATH

finish() {
	echo -e "\e[31m MAKE UBOOT IMAGE FAILED.\e[0m"
	exit -1
}
trap finish ERR

if [ $# != 1 ]; then
	BOARD=rk3288-evb
fi

[ ! -d ${OUT} ] && mkdir ${OUT}
[ ! -d ${OUT}/u-boot ] && mkdir ${OUT}/u-boot
[ ! -d ${OUT}/u-boot/spi ] && mkdir ${OUT}/u-boot/spi

# source命令也称为“点命令”，也就是一个点符号（.）,是bash的内部命令
# source filename 或 . filename
# source filename 与 sh filename 及./filename执行脚本的区别在那里呢？
# 1.当shell脚本具有可执行权限时，用sh filename与./filename执行脚本是没有区别得。./filename是因为当前目录没有在PATH中，所有"."是用来表示当前目录的。
# 2.sh filename 重新建立一个子shell，在子shell中执行脚本里面的语句，该子shell继承父shell的环境变量，但子shell新建的、改变的变量不会被带回父shell，除非使用export。
# 3.source filename：这个命令其实只是简单地读取脚本里面的语句依次在当前shell里面执行，没有建立新的子shell。那么脚本里面所有新建、改变变量的语句都会保存在当前shell里面
# board_configs.sh 做了下面的配置
#	"rockpi4b")
#		DEFCONFIG=rockchip_linux_defconfig
#		DEFCONFIG_MAINLINE=defconfig
#		UBOOT_DEFCONFIG=rock-pi-4b-rk3399_defconfig
#		DTB=rk3399-rock-pi-4b.dtb
#		DTB_MAINLINE=rk3399-rock-pi-4.dtb
#		export ARCH=arm64
#		export CROSS_COMPILE=aarch64-linux-gnu-
#		CHIP="rk3399"
source $LOCALPATH/build/board_configs.sh $BOARD

if [ $? -ne 0 ]; then
	exit
fi

echo -e "\e[36m Building U-boot for ${BOARD} board! \e[0m"
echo -e "\e[36m Using ${UBOOT_DEFCONFIG} \e[0m"

cd ${LOCALPATH}/u-boot
# 编译uboot
make ${UBOOT_DEFCONFIG} all

if  [ "${CHIP}" == "rk322x" ] || [ "${CHIP}" == "rk3036" ]; then
	if [ `grep CONFIG_SPL_OF_CONTROL=y ./.config` ] && \
			! [ `grep CONFIG_SPL_OF_PLATDATA=y .config` ] ; then
		SPL_BINARY=u-boot-spl-dtb.bin
	else
		SPL_BINARY=u-boot-spl-nodtb.bin
	fi
  
	if [ "${DDR_BIN}" ]; then
		# Use rockchip close-source ddrbin.
		dd if=${DDR_BIN} of=spl/${SPL_BINARY}
	fi

	tools/mkimage -n ${CHIP} -T \
		rksd -d spl/${SPL_BINARY} idbloader.img
	cat u-boot-dtb.bin >>idbloader.img
	cp idbloader.img ${OUT}/u-boot/
elif [ "${CHIP}" == "rk3288" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000 --size 1024 1
	tools/mkimage -n rk3288 -T rksd -d ../rkbin/bin/rk32/rk3288_ddr_400MHz_v1.07.bin idbloader.img
	cat ../rkbin/bin/rk32/rk3288_miniloader_v2.54.bin >> idbloader.img
	cp idbloader.img ${OUT}/u-boot/
	echo "idbloader.img is ready"

	$TOOLPATH/loaderimage --pack --uboot ./u-boot.bin uboot.img 0x0

	TOS_TA=`sed -n "/TOSTA=/s/TOSTA=//p" ../rkbin/RKTRUST/RK3288TOS.ini|tr -d '\r'`
	TOS_TA=$(echo ${TOS_TA} | sed "s/tools\/rk_tools\///g")
	$TOOLPATH/loaderimage --pack --trustos ../rkbin/${TOS_TA} ./trust.img 0x8400000

	mv trust.img ${OUT}/u-boot/
	cp uboot.img ${OUT}/u-boot/
elif [ "${CHIP}" == "rk3328" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000 --size 1024 1

	tools/mkimage -n rk3328 -T rksd -d ../rkbin/bin/rk33/rk3328_ddr_333MHz_v1.16.bin idbloader.img
	cat ../rkbin/bin/rk33/rk322xh_miniloader_v2.50.bin >> idbloader.img
	cp idbloader.img ${OUT}/u-boot/	
	cp ../rkbin/bin/rk33/rk3328_loader_ddr333_v1.16.250.bin ${OUT}/u-boot/

	# trust.ini 配置 trust.img镜像包含哪些阶段的安全镜像
	# 如果trust.img只包含了BL31(ATF)的镜像 rkbin/bin/rk33/rk322xh_bl31_v1.42.elf，且地址是0x10000
	cat >trust.ini <<EOF
[VERSION]
MAJOR=1
MINOR=2
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=../rkbin/bin/rk33/rk322xh_bl31_v1.42.elf
ADDR=0x10000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF

	$TOOLPATH/trust_merger --size 1024 1 trust.ini

	cp uboot.img ${OUT}/u-boot/
	cp trust.img ${OUT}/u-boot/
elif [ "${CHIP}" == "rk3399" ]; then  # 走这个分支 CHIP="rk3399"
	# $TOOLPATH ==> TOOLPATH=${LOCALPATH}/rkbin/tools 
	# loaderimage 这个工具是rockchip自己写的一个工具，暂且就认为它把 ./u-boot-dtb.bin 转换为了 uboot.img 镜像了哈，可能它在镜像的前面添加了一个头，包含了些  指定的信息
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000 --size 1024 1
    
	# uboot源代码的tools 目录下有mkimage工具，这个工具可以用来制作不压缩或者压缩的多种可启动镜像文件。 
	# mkimage在制作镜像文件的时候，是在原来的可执行镜像文件的前面加上一个0x40长度的头，记录参数所指定的信息，这样uboot才能识别这个镜像文件的CPU体系结构的、操作系统、加载内存的位置， 入口地址等
	# 
	# -A ==> set architecture to 'arch'          // 用于指定CPU类型，比如ARM
	# -O ==> set operating system to 'os'        // 用于指定操作系统，比如Linux
	# -T ==> set image type to 'type'            // 用于指定image类型，比如Kernel
	# -C ==> set compression type 'comp'         // 指定压缩类型
	# -a ==> set load address to 'addr' (hex)    // 指定image的加载地址
	# -e ==> set entry point to 'ep' (hex)       // 指定内核的入口地址，一般是image的载入地址+0x40（信息头的大小）
	# -n ==> set image name to 'name'            // image在头结构中的命名
	# -d ==> use image data from 'datafile'      // 无头信息的image文件名
	# -x ==> set XIP (execute in place)          // 设置执行位置
	 
	# 网上的资料，说了下各个镜像的作用  https://www.cnblogs.com/lzd626/p/15982648.html
	# 1.DDR相关的rk3399_ddr_800MHz_v1.09.bin、
	#   USB相关的rk3399_usbplug_v1.09.bin、
	#   miniloader(瑞芯微修改的一个bootloader,可以理解成spl)相关的rk3399_miniloader_v1.09.bin。
	#   boot_merger将这三个bin文件最后合并成rk3399_loader_v1.09.109.bin
	# 2.使用trust_merger，参数为RK3399TRUST.ini，生成trust.img；
	# 3.使用loaderimage将u-boot.bin变成uboot.img；	 

	# rk3399_ddr_800MHz_v1.20.bin ==> 这个镜像应该使用初始化DDR的 ==> 通过mkimage添加了一个0x40长度的头 ==> 生成了镜像 idbloader.img 
	tools/mkimage -n rk3399 -T rksd -d ../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.20.bin idbloader.img
	# rk3399_miniloader_v1.19.bin ==> 瑞芯微修改的一个bootloader,可以理解成spl,运⾏在 ddr 中，负责完成系统的 lowlevel 初始化、后级固件加载（trust.img 和 uboot.img）
	# 通过 cat命令将这个镜像拼接到idbloader.img镜像的末尾，形成一个统一的镜像 idbloader.img 
	cat ../rkbin/bin/rk33/rk3399_miniloader_v1.19.bin >> idbloader.img
	# 将idbloader.img 拷贝到 ${OUT}/u-boot/ 目录下
	cp idbloader.img ${OUT}/u-boot/

	# 下面的流程是与上面类似的，做出来的镜像 是 给 spinor flash 使用的
	tools/mkimage -n rk3399 -T rkspi -d ../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.20.bin idbloader-spi.img
	cat ../rkbin/bin/rk33/rk3399_miniloader_spinor_v1.14.bin >> idbloader-spi.img
	# 将idbloader-spi.img 拷贝到 ${OUT}/u-boot/ 目录下
	cp idbloader-spi.img ${OUT}/u-boot/spi

	# 下面两个镜像，如上说的“boot_merger将这三个bin文件最后合并成rk3399_loader_v1.09.109.bin”
	# 也是一个是针对spinor flash的，一个是针对非spinor flash的
	cp ../rkbin/bin/rk33/rk3399_loader_v1.20.119.bin ${OUT}/u-boot/
	cp ../rkbin/bin/rk33/rk3399_loader_spinor_v1.20.126.bin ${OUT}/u-boot/spi

	# 模拟输入，创建一个 trust.ini 的文件，trust_merger 用这个配置文件来生成镜像trust.img 
	# 通过各个阶段 BL30 BL31 BL32 BL33 的 SEC配置， 配置各个阶段的镜像是否 输出到 trust.img镜像中，
	# 下面的配置文件 指定 安全启动镜像trust.img 中只包含了BL31 ATF的镜像文件:rkbin/bin/rk33/rk3399_bl31_v1.26.elf，且这个镜像存放在0x10000
	cat >trust.ini <<EOF
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=../rkbin/bin/rk33/rk3399_bl31_v1.26.elf
ADDR=0x10000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF
	# trust_merger 根据配置文件 trust.ini 来 生成 trust.img镜像 ==> 包含了指定的阶段的镜像在里面了，比如上面 BL31(ATF)的 rk3399_bl31_v1.26.elf 
	$TOOLPATH/trust_merger --size 1024 1 trust.ini

	cp uboot.img ${OUT}/u-boot/  # uboot.img 是最开始通过 loaderimage 生成的
	cp trust.img ${OUT}/u-boot/  # trust_merger生成的 trust.img镜像 ==> trust.img镜像 根据trust.ini来看只包含了 BL31(ATF)的 rk3399_bl31_v1.26.elf 

	# 下面是模式输入生成一个配置文件 spi.ini，给firmwareMerger用来生成镜像Firmware.img， firmwareMerger用来将各种firmware合并在一起
	# 如下有 3个用户部分
	# UserPart1 【SPL】   ==>名字:IDBlock==>存放位置:0x40(扇区)  ,大小:0x7C0(扇区)==>包含镜像:../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.20.bin, 
	#                                                                                         ../rkbin/bin/rk33/rk3399_miniloader_spinor_v1.14.bin
	# UserPart2 【u-boot】==>名字:uboot  ==>存放位置:0x1000(扇区),大小:0x800(扇区)==>包含镜像:./uboot.img 
	# UserPart3 【trust】 ==>名字:trust  ==>存放位置:0x1800(扇区),大小:0x800(扇区)==>包含镜像:./trust.img
	# 所以合并后生成的Firmware.img就包含了以上相关的镜像，而且他们的存放的位置都已经明确了
	# Firmware.img后面会改名，以及它包含的各个子镜像，见下面的分析
	cat > spi.ini <<EOF
[System]
FwVersion=18.08.03
BLANK_GAP=1
FILL_BYTE=0
[UserPart1]
Name=IDBlock
Flag=0
Type=2
File=../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.20.bin,../rkbin/bin/rk33/rk3399_miniloader_spinor_v1.14.bin
PartOffset=0x40
PartSize=0x7C0
[UserPart2]
Name=uboot
Type=0x20
Flag=0
File=./uboot.img
PartOffset=0x1000
PartSize=0x800
[UserPart3]
Name=trust
Type=0x10
Flag=0
File=./trust.img
PartOffset=0x1800
PartSize=0x800
EOF
	$TOOLPATH/firmwareMerger -P spi.ini ${OUT}/u-boot/spi
	# Firmware.img 改名为uboot-trust-spi.img，并保存到${OUT}/u-boot/spi/uboot-trust-spi.img 
	# uboot-trust-spi.img ==> 包含了三个部分: IDBlock + trust.img + uboot.img，每个部分的存放位置见上面的分析 
	#     IDBlock   ==> 包含了../rkbin/bin/rk33/rk3399_ddr_800MHz_v1.20.bin【初始化DDR的代码镜像】 +  ../rkbin/bin/rk33/rk3399_miniloader_spinor_v1.14.bin【SPL:加载BL31的ATF镜像】
	#     trust.img ==> 如上分析 只包含了BL31 ATF的镜像文件:rkbin/bin/rk33/rk3399_bl31_v1.26.elf【ATF镜像】
	#     uboot.img ==> 包含加了个uboot头的 u-boot-dtb.bin 【u-boot加载内核用的镜像】
	mv ${OUT}/u-boot/spi/Firmware.img ${OUT}/u-boot/spi/uboot-trust-spi.img
	mv ${OUT}/u-boot/spi/Firmware.md5 ${OUT}/u-boot/spi/uboot-trust-spi.img.md5

elif [ "${CHIP}" == "rk3399pro" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000 --size 1024 1

	DDR_TYPE=("rk3399pro_ddr_800MHz_v1.20.bin" "rk3399_ddr_800MHz_v1.22_fix_row_3_4.bin")
	DDR_TYPE_SHORT=("" "-3GB-ddr")
	for num in {0..1}
	do
		tools/mkimage -n rk3399pro -T rksd -d ../rkbin/bin/rk33/${DDR_TYPE[$num]} idbloader${DDR_TYPE_SHORT[$num]}.img
		cat ../rkbin/bin/rk33/rk3399pro_miniloader_v1.15.bin >> idbloader${DDR_TYPE_SHORT[$num]}.img
		cp idbloader${DDR_TYPE_SHORT[$num]}.img ${OUT}/u-boot/

		tools/mkimage -n rk3399pro -T rkspi -d ../rkbin/bin/rk33/${DDR_TYPE[$num]} idbloader-spi${DDR_TYPE_SHORT[$num]}.img
		cat ../rkbin/bin/rk33/rk3399_miniloader_spinor_v1.14.bin >> idbloader-spi${DDR_TYPE_SHORT[$num]}.img
		cp idbloader-spi${DDR_TYPE_SHORT[$num]}.img ${OUT}/u-boot/spi

		cp ../rkbin/bin/rk33/rk3399pro_loader_v1.20.115.bin ${OUT}/u-boot/
		cp ../rkbin/bin/rk33/rk3399pro_loader_3GB_ddr_v1.22.115.bin ${OUT}/u-boot/
		cp ../rkbin/bin/rk33/rk3399pro_npu_loader_v1.02.102.bin ${OUT}/u-boot/
		cp ../rkbin/bin/rk33/rk3399_loader_spinor_v1.15.114.bin ${OUT}/u-boot/spi
	done

	cat >trust.ini <<EOF
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=../rkbin/bin/rk33/rk3399pro_bl31_v1.22.elf
ADDR=0x10000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF

	$TOOLPATH/trust_merger --size 1024 1 trust.ini

	cp uboot.img ${OUT}/u-boot/
	cp trust.img ${OUT}/u-boot/

	DDR_TYPE=("rk3399pro_ddr_800MHz_v1.20.bin" "rk3399_ddr_800MHz_v1.22_fix_row_3_4.bin")
	DDR_TYPE_SHORT=("" "-3GB-ddr")
	for num in {0..1}
	do
		cat > spi.ini <<EOF
[System]
FwVersion=18.08.03
BLANK_GAP=1
FILL_BYTE=0
[UserPart1]
Name=IDBlock
Flag=0
Type=2
File=../rkbin/bin/rk33/${DDR_TYPE[$num]},../rkbin/bin/rk33/rk3399pro_miniloader_v1.15.bin
PartOffset=0x40
PartSize=0x7C0
[UserPart2]
Name=uboot
Type=0x20
Flag=0
File=./uboot.img
PartOffset=0x1000
PartSize=0x800
[UserPart3]
Name=trust
Type=0x10
Flag=0
File=./trust.img
PartOffset=0x1800
PartSize=0x800
EOF
		$TOOLPATH/firmwareMerger -P spi.ini ${OUT}/u-boot/spi
		mv ${OUT}/u-boot/spi/Firmware.img ${OUT}/u-boot/spi/uboot-trust-spi${DDR_TYPE_SHORT[$num]}.img
		mv ${OUT}/u-boot/spi/Firmware.md5 ${OUT}/u-boot/spi/uboot-trust-spi${DDR_TYPE_SHORT[$num]}.img.md5
	done
elif [ "${CHIP}" == "rk3128" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img

	dd if=../rkbin/rk31/rk3128_ddr_300MHz_v2.06.bin of=DDRTEMP bs=4 skip=1
	tools/mkimage -n rk3128 -T rksd -d DDRTEMP idbloader.img
	cat ../rkbin/rk31/rk312x_miniloader_v2.40.bin >> idbloader.img
	cp idbloader.img ${OUT}/u-boot/
	cp ../rkbin/rk31/rk3128_loader_v2.05.240.bin ${OUT}/u-boot/

	$TOOLPATH/loaderimage --pack --trustos ../rkbin/rk31/rk3126_tee_ta_v1.27.bin trust.img

	cp uboot.img ${OUT}/u-boot/
	mv trust.img ${OUT}/u-boot/
elif [ "${CHIP}" == "rk3308" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x600000 --size 1024 1

	tools/mkimage -n rk3308 -T rksd -d ../rkbin/bin/rk33/rk3308_ddr_589MHz_uart0_m0_v1.26.bin idbloader.img
	cat ../rkbin/bin/rk33/rk3308_miniloader_emmc_port_support_sd_20190717.bin >> idbloader.img
	cp idbloader.img ${OUT}/u-boot/
	cp ../rkbin/bin/rk33/rk3308_loader_uart0_m0_emmc_port_support_sd_20190717.bin ${OUT}/u-boot

	cat >trust.ini <<EOF
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=../rkbin/bin/rk33/rk3308_bl31_v2.10.elf
ADDR=0x00010000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF

	$TOOLPATH/trust_merger --size 1024 1 trust.ini

	cp uboot.img ${OUT}/u-boot/
	cp trust.img ${OUT}/u-boot/
elif [ "${CHIP}" == "px30" ]; then
	$TOOLPATH/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000 --size 1024 1

	tools/mkimage -n px30 -T rksd -d ../rkbin/bin/rk33/px30_ddr_333MHz_v1.14.bin idbloader.img
	cat ../rkbin/bin/rk33/px30_miniloader_v1.20.bin >> idbloader.img
	cp idbloader.img ${OUT}/u-boot/
	cp ../rkbin/bin/rk33/px30_loader_v1.14.120.bin ${OUT}/u-boot

	cat >trust.ini <<EOF
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=../rkbin/bin/rk33/px30_bl31_v1.18.elf
ADDR=0x00010000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.img
EOF

	$TOOLPATH/trust_merger --size 1024 1 trust.ini

	cp uboot.img ${OUT}/u-boot/
	cp trust.img ${OUT}/u-boot/
fi
echo -e "\e[36m U-boot IMAGE READY! \e[0m"
