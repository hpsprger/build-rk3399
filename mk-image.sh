#!/bin/bash -e

# 编译内核时mk-kernel.sh 中调用该脚本的命令 ==>  ./build/mk-image.sh -c rk3399 -t boot    -b rockpi4b      ==> ./build/mk-image.sh -c ${CHIP} -t boot -b ${BOARD}
# rootfs做好了之后，再执行该脚本的命令      ==> 1: build/mk-image.sh -c rk3399 -t system  -r rootfs/linaro-rootfs.img
#                                               2: build/mk-image.sh -c rk3399 -b rockpi4 -t system  -r rootfs/linaro-rootfs.img

LOCALPATH=$(pwd)
OUT=${LOCALPATH}/out
TOOLPATH=${LOCALPATH}/rkbin/tools
EXTLINUXPATH=${LOCALPATH}/build/extlinux
CHIP=""
TARGET=""
ROOTFS_PATH=""
BOARD=""

PATH=$PATH:$TOOLPATH

# partitions.sh里面计算出了各个区的起始位置与大小
# LOADER1_SIZE=8000
# RESERVED1_SIZE=128
# RESERVED2_SIZE=8192
# LOADER2_SIZE=8192
# ATF_SIZE=8192
# BOOT_SIZE=1048576
# 
# SYSTEM_START=0
# LOADER1_START=64
# RESERVED1_START=$(expr ${LOADER1_START} + ${LOADER1_SIZE})
# RESERVED2_START=$(expr ${RESERVED1_START} + ${RESERVED1_SIZE})
# LOADER2_START=$(expr ${RESERVED2_START} + ${RESERVED2_SIZE})
# ATF_START=$(expr ${LOADER2_START} + ${LOADER2_SIZE})
# BOOT_START=$(expr ${ATF_START} + ${ATF_SIZE})
# ROOTFS_START=$(expr ${BOOT_START} + ${BOOT_SIZE})
source $LOCALPATH/build/partitions.sh

usage() {
	echo -e "\nUsage: build/mk-image.sh -c rk3399 -t system -r rk-rootfs-build/linaro-rootfs.img \n"
	echo -e "       build/mk-image.sh -c rk3399 -t boot -b rockpi4b\n"
}
finish() {
	echo -e "\e[31m MAKE IMAGE FAILED.\e[0m"
	exit -1
}
trap finish ERR

# 脚本中的命令 ==> ./build/mk-image.sh -c rk3399 -t boot -b rockpi4b
# 命令行中输入的参数  赋值到对应的变量中去 
OLD_OPTIND=$OPTIND
while getopts "c:t:r:b:h" flag; do
	case $flag in
		c)
			CHIP="$OPTARG"
			;;
		t)
			TARGET="$OPTARG"
			;;
		r)
			ROOTFS_PATH="$OPTARG"
			;;
		b)
			BOARD="$OPTARG"
			;;
	esac
done
OPTIND=$OLD_OPTIND

# "${EXTLINUXPATH}/${CHIP}.conf" ==> /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux/rk3399.conf
# 判断这个文件是否存在 ==> [ -f FILE ] 如果 FILE 存在且是一个普通文件则为真
# 下面的判断则是这个文件不存在的话
if [ ! -f "${EXTLINUXPATH}/${CHIP}.conf" ]; then
	CHIP="rk3288"
fi

# $CHIP  $TARGET 有一个为空 就是错误
if [ ! $CHIP ] && [ ! $TARGET ]; then
	usage
	exit
fi

if [[ "${CHIP}" == "rk3308" ]]; then
	source $LOCALPATH/build/rockpis-partitions.sh
fi

# 编译内核的脚本中，在内核编译完后，会执行该脚本 ==> -t boot ==> 会调用 generate_boot_image这个函数 
# 编译内核时mk-kernel.sh 中调用该脚本的命令 ==>  ./build/mk-image.sh -c rk3399 -t boot    -b rockpi4b      ==> ./build/mk-image.sh -c ${CHIP} -t boot -b ${BOARD}
generate_boot_image() {
	BOOT=${OUT}/boot.img
	rm -rf ${BOOT}

	echo -e "\e[36m Generate Boot image start\e[0m"

	if [[ "${CHIP}" == "rk3308" ]]; then
		# 100MB
		mkfs.vfat -n "boot" -S 512 -C ${BOOT} $((100 * 1024))
	else #rk3399 走这个分支
		# 500Mb 
		# man mkfs.vfat
		# -n 指定名字 
		# -S Specify the number of bytes per logical sector.
		# -C  Create the file given as DEVICE on the command line, and write the to-be-created filesystem to it.  This can be used to create the new filesystem in a file instead of on a real device, and to  avoid using dd in advance to create a file of appropriate size.
		# 创建这个镜像文件 500M 
		mkfs.vfat -n "boot" -S 512 -C ${BOOT} $((500 * 1024))
	fi
    
	# Linux mmd命令用于在MS-DOS文件系统中建立目录
	# man mmd
	# 反正就是在这个镜像中填充对应的镜像，最后要给windows那个烧录工具烧写到SD卡上去的
	mmd -i ${BOOT} ::/extlinux
	if [ "${BOARD}" == "rockpi4a" ] || [ "${BOARD}" == "rockpi4b" ] ||  [ "${BOARD}" == "rockpis" ] ; then
		mmd -i ${BOOT} ::/overlays
	fi

	mcopy -i ${BOOT} -s ${EXTLINUXPATH}/${CHIP}.conf ::/extlinux/extlinux.conf
	mcopy -i ${BOOT} -s ${OUT}/kernel/* ::

	echo -e "\e[36m Generate Boot image : ${BOOT} success! \e[0m"
}

# rootfs做好了后会执行该脚本 ==> -t boot ==> 会调用 generate_system_image 这个函数 
# rootfs做好了之后，再执行该脚本的命令      ==> 1: build/mk-image.sh -c rk3399 -t system  -r rootfs/linaro-rootfs.img
#                                               2: build/mk-image.sh -c rk3399 -b rockpi4 -t system  -r rootfs/linaro-rootfs.img
generate_system_image() {
	if [ ! -f "${OUT}/boot.img" ]; then
		echo -e "\e[31m CAN'T FIND BOOT IMAGE \e[0m"
		usage
		exit
	fi

	if [ ! -f "${ROOTFS_PATH}" ]; then
		echo -e "\e[31m CAN'T FIND ROOTFS IMAGE \e[0m"
		usage
		exit
	fi

	SYSTEM=${OUT}/system.img  # 最终的大系统的镜像名称
	rm -rf ${SYSTEM}

	echo "Generate System image : ${SYSTEM} !"

	# last dd rootfs will extend gpt image to fit the size,
	# but this will overrite the backup table of GPT
	# will cause corruption error for GPT
	IMG_ROOTFS_SIZE=$(stat -L --format="%s" ${ROOTFS_PATH})
	GPTIMG_MIN_SIZE=$(expr $IMG_ROOTFS_SIZE + \( ${LOADER1_SIZE} + ${RESERVED1_SIZE} + ${RESERVED2_SIZE} + ${LOADER2_SIZE} + ${ATF_SIZE} + ${BOOT_SIZE} + 35 \) \* 512)
	GPT_IMAGE_SIZE=$(expr $GPTIMG_MIN_SIZE \/ 1024 \/ 1024 + 2)

	dd if=/dev/zero of=${SYSTEM} bs=1M count=0 seek=$GPT_IMAGE_SIZE

	if [ "$BOARD" == "rockpi4" ]; then
		parted -s ${SYSTEM} mklabel gpt
		parted -s ${SYSTEM} unit s mkpart loader1 ${LOADER1_START} $(expr ${RESERVED1_START} - 1)
		# parted -s ${SYSTEM} unit s mkpart reserved1 ${RESERVED1_START} $(expr ${RESERVED2_START} - 1)
		# parted -s ${SYSTEM} unit s mkpart reserved2 ${RESERVED2_START} $(expr ${LOADER2_START} - 1)
		parted -s ${SYSTEM} unit s mkpart loader2 ${LOADER2_START} $(expr ${ATF_START} - 1)
		parted -s ${SYSTEM} unit s mkpart trust ${ATF_START} $(expr ${BOOT_START} - 1)
		parted -s ${SYSTEM} unit s mkpart boot ${BOOT_START} $(expr ${ROOTFS_START} - 1)
		parted -s ${SYSTEM} set 4 boot on
		parted -s ${SYSTEM} -- unit s mkpart rootfs ${ROOTFS_START} -34s
	else
		parted -s ${SYSTEM} mklabel gpt
		parted -s ${SYSTEM} unit s mkpart boot ${BOOT_START} $(expr ${ROOTFS_START} - 1)
		parted -s ${SYSTEM} set 1 boot on
		parted -s ${SYSTEM} -- unit s mkpart rootfs ${ROOTFS_START} -34s
	fi

	if [ "$CHIP" == "rk3328" ] || [ "$CHIP" == "rk3399" ] || [ "$CHIP" == "rk3399pro" ]; then
		ROOT_UUID="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
	elif [ "$CHIP" == "rk3308" ] || [ "$CHIP" == "px30" ]; then
		ROOT_UUID="614e0000-0000-4b53-8000-1d28000054a9"
	else
		ROOT_UUID="69DAD710-2CE4-4E3C-B16C-21A1D49ABED3"
	fi

	if [ "$BOARD" == "rockpi4" ]; then
		gdisk ${SYSTEM} <<EOF
x
c
5
${ROOT_UUID}
w
y
EOF
	else
		gdisk ${SYSTEM} <<EOF
x
c
2
${ROOT_UUID}
w
y
EOF
	fi

	# burn u-boot
	case ${CHIP} in
	rk322x | rk3036 )
		dd if=${OUT}/u-boot/idbloader.img of=${SYSTEM} seek=${LOADER1_START} conv=notrunc
		;;
	px30 | rk3288 | rk3308 | rk3328 | rk3399 | rk3399pro )
		dd if=${OUT}/u-boot/idbloader.img of=${SYSTEM} seek=${LOADER1_START} conv=notrunc
		dd if=${OUT}/u-boot/uboot.img of=${SYSTEM} seek=${LOADER2_START} conv=notrunc
		dd if=${OUT}/u-boot/trust.img of=${SYSTEM} seek=${ATF_START} conv=notrunc
		;;
	*)
		;;
	esac

	# burn boot image
	dd if=${OUT}/boot.img of=${SYSTEM} conv=notrunc seek=${BOOT_START}

	# burn rootfs image
	dd if=${ROOTFS_PATH} of=${SYSTEM} conv=notrunc,fsync seek=${ROOTFS_START}
}


# ./build/mk-image.sh -c rk3399 -t boot -b rockpi4b ==> -t ==> TARGET 为 boot ==> 调用函数 generate_boot_image 
if [ "$TARGET" = "boot" ]; then
	generate_boot_image
elif [ "$TARGET" == "system" ]; then
	generate_system_image
fi
