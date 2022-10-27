#!/bin/bash -e

# 编译内核时mk-kernel.sh 中调用该脚本的命令 ==>  ./build/mk-image.sh -c rk3399 -t boot    -b rockpi4b      ==> ./build/mk-image.sh -c ${CHIP} -t boot -b ${BOARD}
# rootfs做好了之后，再执行该脚本的命令      ==> 1: build/mk-image.sh -c rk3399            -t system  -r rootfs/linaro-rootfs.img
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
	
	# 命令参数中的 -r rootfs/linaro-rootfs.img  ==> ${ROOTFS_PATH}
	# man stat ==>  stat - display file or file system status
	# 使用stat --format 命令在脚本中获取指定文件大小
	# -L, --dereference     follow links  如果是链接文件，则获取原文件信息
	# -c  --format=FORMAT   use the specified FORMAT instead of the default;
	#                       output a newline after each use of FORMAT
	#                       自定义输出格式，结尾有换行
	# %s   Total size, in bytes   文件大小（单位byte
	# https://blog.51cto.com/colinzhouyj/1288580
	IMG_ROOTFS_SIZE=$(stat -L --format="%s" ${ROOTFS_PATH})
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
	# 下面的这两句话就是计算出了 GPTIMG_MIN_SIZE GPT_IMAGE_SIZE 这个值的大小
	GPTIMG_MIN_SIZE=$(expr $IMG_ROOTFS_SIZE + \( ${LOADER1_SIZE} + ${RESERVED1_SIZE} + ${RESERVED2_SIZE} + ${LOADER2_SIZE} + ${ATF_SIZE} + ${BOOT_SIZE} + 35 \) \* 512)
	GPT_IMAGE_SIZE=$(expr $GPTIMG_MIN_SIZE \/ 1024 \/ 1024 + 2)

	# 通过dd命令 生成一个镜像文件 ==> SYSTEM=${OUT}/system.img
	# if = 文件名：输入文件名，缺省为标准输入。即指定源文件。< if = input file >
	# of = 文件名：输出文件名，缺省为标准输入。即指定目的文件。 < of = output file >
	# ibs = bytes：一次读入bytes个字节，即指定一个块大小为bytes字节；
	# obs = bytes：一次输出bytes个字节，即指定一个块大小为bytes字节；
	# cbs = bytes：一次转换bytes个字节，即指定转换缓冲区的大小
	# bs = bytes：同时设置读入/输出的块大小为bytes个字节
	# count = blocks：仅拷贝blocks个块，块大小等于 ibs 指定的字节数。
	# conv = conversion：用指定的参数转换文件； notrunc：不截短输出文件； ascii：转换ebcdic为ascii等等 
	# skip = blocks：从输入文件开头跳过blocks个块后再开始复制
	# seek = blocks：从输出文件开头跳过blocks个块后才开始复制；注意：通常只用当输出文件是磁盘或磁带时才有效，即备份到磁盘或磁带时才有效
	# https://blog.csdn.net/qq_33141353/article/details/119748202?spm=1001.2101.3001.6650.3&utm_medium=distribute.pc_relevant.none-task-blog-2~default~CTRLIST~Rate-3-119748202-blog-89007666.pc_relevant_recovery_v2&depth_1-utm_source=distribute.pc_relevant.none-task-blog-2~default~CTRLIST~Rate-3-119748202-blog-89007666.pc_relevant_recovery_v2&utm_relevant_index=6
	dd if=/dev/zero of=${SYSTEM} bs=1M count=0 seek=$GPT_IMAGE_SIZE

	# parted 用于对磁盘(或RAID磁盘)进行分区及管理，与fdisk分区工具相比，支持2TB以上的磁盘分区，并且允许调整分区的大小
	# parted磁盘分区的介绍
	#     parted 是一个操作硬盘分区的程序。它支持多种分区表类型，包括 MS-DOS 和 GPT。
	#     parted允许用户创建、删除、调整、缩减、移动和复制分区，以及重新组织硬盘的使用，复制数据到新的硬盘上。
	#     它是非交互创建磁盘分区的命令。
	# parted与fdisk的区别
	#     fdisk只能支持MS-DOS，parted支持MS-DOS和GPT。
	#     fdisk 命令不支持用户在大于 2TB 的硬盘上创建硬盘分区， 但 parted 支持。
	#     parted允许用户调整分区大小， 但当缩减分区空间的时候，多数情况下会得到错误消息
	# 查看分区信息 ==> parted /dev/sdb print
	# 创建分区 ==> parted /dev/sdb mkpart primary xfs 1 1G
	# 删除分区 ==> parted /dev/sdb rm 4  或者  parted /dev/sdb rm 1
	# man parted ==> -s 不给用户输出提示信息
	#                mklabel label-type ==>  Create a new disklabel (partition table) of label-type.  label-type should be one of "aix", "amiga", "bsd", "dvh", "gpt", "loop", "mac", "msdos", "pc98", or "sun".
	#                unit unit  ==> Set unit as the unit to use when displaying locations and sizes, and for interpreting those given by the user when not suffixed with an explicit unit.
	#                mkpart [part-type name fs-type] start end ==> Create  a  new  partition. part-type may be specified only with msdos and dvh partition tables, it should be one of "primary", "logical", or "extended".  name is required for GPT partition tables and fs-type is optional.  fs-type can be one of "btrfs", "ext2", "ext3", "ext4", "fat16", "fat32", "hfs", "hfs+", "linux-swap", "ntfs", "reiserfs", "udf", or "xfs"
	#                set partition flag state ==> Change the state of the flag on partition to state.  Supported flags are: "boot", "root", "swap", "hidden", "raid", "lvm", "lba", "legacy_boot", "irst", "msftres", "esp", "chromeos_kernel"  and "palo".  state should be either "on" or "off".
	#                
	if [ "$BOARD" == "rockpi4" ]; then  # -b rockpi4 ==> $BOARD ==> 有指定的时候 
	    # ${SYSTEM} ==> SYSTEM=${OUT}/system.img
		parted -s ${SYSTEM} mklabel gpt
		parted -s ${SYSTEM} unit s mkpart loader1 ${LOADER1_START} $(expr ${RESERVED1_START} - 1)
		# parted -s ${SYSTEM} unit s mkpart reserved1 ${RESERVED1_START} $(expr ${RESERVED2_START} - 1)
		# parted -s ${SYSTEM} unit s mkpart reserved2 ${RESERVED2_START} $(expr ${LOADER2_START} - 1)
		parted -s ${SYSTEM} unit s mkpart loader2 ${LOADER2_START} $(expr ${ATF_START} - 1)
		parted -s ${SYSTEM} unit s mkpart trust ${ATF_START} $(expr ${BOOT_START} - 1)
		parted -s ${SYSTEM} unit s mkpart boot ${BOOT_START} $(expr ${ROOTFS_START} - 1)
		parted -s ${SYSTEM} set 4 boot on
		parted -s ${SYSTEM} -- unit s mkpart rootfs ${ROOTFS_START} -34s
	else   # $BOARD ==>  没有指定的时候                
		parted -s ${SYSTEM} mklabel gpt
		parted -s ${SYSTEM} unit s mkpart boot ${BOOT_START} $(expr ${ROOTFS_START} - 1)
		parted -s ${SYSTEM} set 1 boot on
		parted -s ${SYSTEM} -- unit s mkpart rootfs ${ROOTFS_START} -34s
	fi
     
	# $CHIP ==> -c rk3399 
	if [ "$CHIP" == "rk3328" ] || [ "$CHIP" == "rk3399" ] || [ "$CHIP" == "rk3399pro" ]; then
		ROOT_UUID="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"   # 用这个分支
	elif [ "$CHIP" == "rk3308" ] || [ "$CHIP" == "px30" ]; then
		ROOT_UUID="614e0000-0000-4b53-8000-1d28000054a9"
	else
		ROOT_UUID="69DAD710-2CE4-4E3C-B16C-21A1D49ABED3"
	fi

	# -b rockpi4 ==> $BOARD ==> 有指定的时候
	if [ "$BOARD" == "rockpi4" ]; then
		# gdisk 创建和维护磁盘分区命令(GPT分区方案) ==> 下面就是模拟用户执行这个命令的时候，用户的输入
		gdisk ${SYSTEM} <<EOF
x
c
5
${ROOT_UUID}
w
y
EOF
	else # $BOARD ==>  没有指定的时候
		# gdisk 创建和维护磁盘分区命令(GPT分区方案)	==> 下面就是模拟用户执行这个命令的时候，用户的输入
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
	# -c rk3399 ==> ${CHIP}
	case ${CHIP} in
	rk322x | rk3036 )
		dd if=${OUT}/u-boot/idbloader.img of=${SYSTEM} seek=${LOADER1_START} conv=notrunc
		;;
	px30 | rk3288 | rk3308 | rk3328 | rk3399 | rk3399pro )
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
		# rk3399走这个分支 
		# dd 的使用上面也有讲解
		# 这里通过dd 将 idbloader.img   trust.img  uboot.img 这几个镜像 写入到镜像文件中去 
		# conv = conversion：用指定的参数转换文件； notrunc：不截短输出文件； ascii：转换ebcdic为ascii等等 
		# skip = blocks：从输入文件开头跳过blocks个块后再开始复制
		# seek = blocks：从输出文件开头跳过blocks个块后才开始复制；注意：通常只用当输出文件是磁盘或磁带时才有效，即备份到磁盘或磁带时才有效
		dd if=${OUT}/u-boot/idbloader.img of=${SYSTEM} seek=${LOADER1_START} conv=notrunc
		dd if=${OUT}/u-boot/uboot.img of=${SYSTEM} seek=${LOADER2_START} conv=notrunc
		dd if=${OUT}/u-boot/trust.img of=${SYSTEM} seek=${ATF_START} conv=notrunc
		;;
	*)
		;;
	esac

	# burn boot image
	# dd 的使用上面也有讲解
	# 这里通过dd 将 boot.img 这几个镜像 写入到镜像文件中去 
	# conv = conversion：用指定的参数转换文件； notrunc：不截短输出文件； ascii：转换ebcdic为ascii等等 
	# skip = blocks：从输入文件开头跳过blocks个块后再开始复制
	# seek = blocks：从输出文件开头跳过blocks个块后才开始复制；注意：通常只用当输出文件是磁盘或磁带时才有效，即备份到磁盘或磁带时才有效
	dd if=${OUT}/boot.img of=${SYSTEM} conv=notrunc seek=${BOOT_START}

	# burn rootfs image
	# dd 的使用上面也有讲解
	# 这里通过dd 将 boot.img 这几个镜像 写入到镜像文件中去 
	# conv = conversion：用指定的参数转换文件； notrunc：不截短输出文件； ascii：转换ebcdic为ascii等等 
	# skip = blocks：从输入文件开头跳过blocks个块后再开始复制
	# seek = blocks：从输出文件开头跳过blocks个块后才开始复制；注意：通常只用当输出文件是磁盘或磁带时才有效，即备份到磁盘或磁带时才有效
	# ${ROOTFS_PATH}  ==>  -r rootfs/linaro-rootfs.img 
	# ${SYSTEM}  ==>  ${OUT}/system.img  # 最终的大系统的镜像名称
	dd if=${ROOTFS_PATH} of=${SYSTEM} conv=notrunc,fsync seek=${ROOTFS_START}
}

# ./build/mk-image.sh -c rk3399 -t boot -b rockpi4b ==> -t ==> TARGET 为 boot ==> 调用函数 generate_boot_image 
if [ "$TARGET" = "boot" ]; then
	generate_boot_image
elif [ "$TARGET" == "system" ]; then
	generate_system_image
fi
