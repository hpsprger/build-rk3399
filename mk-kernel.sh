#!/bin/bash -e  
                       # #! /bin/bash，使用这个路径下的sh实现来执行下面的shell scirpt
                       # #! /bin/sh，使用这个路径下的sh实现来执行下面的shell scirpt
                       # 这第一行代码通常被称为hashbang或shebang
                       # #! /bin/bash -ex
                       # -e: 如果shell command中的任何一行failed，整个shell script file的运行会在这个command处立刻终止。
                       # -x: 在shell script的执行过程中，将command以及参数全部在标准输出中console出来
                       # -e的参数的作用是： 每条指令之后后，都可以用#？去判断他的返回值，零就是正确执行，非零就是执行有误，加了-e之后，就不用自己写代码去判断返回值，返回非零，脚本就会退出
                       # 注意#号后面要加一个空格 
LOCALPATH=$(pwd)       # 获取当前的绝对路径并赋值给变量LOCALPATH ==> /home/hpsp/rock_space/rockpi_4b/rockchip-bsp 
OUT=${LOCALPATH}/out   # OUT变量值  ==> /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/out  
EXTLINUXPATH=${LOCALPATH}/build/extlinux  # EXTLINUXPATH变量值  ==> /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux 
BOARD=$1               # 将传入的第一个参数"rockpi4b" 赋值给 BOARD ==> ./build/mk-kernel.sh rockpi4b

# Shell中的 test 命令用于检查某个条件是否成立，它可以进行数值、字符和文件三个方面的测试
# test 字符串测试 ==>  
#      = 等于则为真
#     != 不相等则为真
#     -z 字符串	字符串的长度为零则为真
#     -n 字符串	字符串的长度不为零则为真
# test 数值测试 ==>  -gt 大于则为真 等等
# $* 传递给脚本或函数的所有参数。
# $@ 传递给脚本或函数的所有参数。
# 在没有双引号包裹时，$*与 $@相同：都是数组, 
# $*与 $@的相同点：当它们在没有被双引号包裹时，两者是没有区别，都代表一个包含接收到的所有参数的数组，各个数组元素是传入的独立参数
# 被双引号包裹时，$*与 $@不同："$@"为数组，"$*"为一个字符串;$@仍然是一个数组，每个参数依然是分割独立的；但当$*被双引号包裹时，SHELL会将所有参数整合为一个字符串
# tr，translate的简写，用于字符转换、压缩重复字符或删除文件中的控制字符。
# tr指令从标准输入设备读取数据，经过字符串转译后，将结果输出标准输出设备（只接受标准输入，不接受文件参数
# echo "$@" | tr " " "\n" ==> ./build/mk-kernel.sh rockpi4b  123 456 789  ==> 
# sort -V ==> 在文本内进行自然版本排序
# ./build/mk-kernel.sh rockpi4b 456 789 123 
# 123
# 456
# 789
# rockpi4b
# head -n 1 ==> 显示文件前1行 ==> 123 
# version_gt() 所以这个函数的功能就是 从传递给这个函数的所有参数 分割开来，然后按自然顺序排序，再显示第一行的内容，
# 与传递给这个函数的第一个参数进行比较【注意这里的$1是表示传递给这个函数的第一个参数，而不是传递给这个脚本的第一个参数】，不相等的话则为真
# version_gt "4.8" "4.5"
version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }

finish() {
	#-e：激活转义字符。使用-e选项时,若字符串中出现以下字符，则特别加以处理，而不会将它当成一般文字输出  \a  \b ... 
	# \e[0m 将颜色重新置回  颜色码：重置=0，黑色=30，红色=31，绿色=32，黄色=33，蓝色=34，洋红=35，青色=36，白色=37
	echo -e "\e[31m MAKE KERNEL IMAGE FAILED.\e[0m"  
	# 在shell脚本中，如果命令正常执行了，那么会返回0。就是上面判断的$?这个符号，得到的值是0，而如果返回的不是0，就意味着命令行没有正确执行成功
	# exit n 退出shell脚本，并设置退出码为n
	# exit 退出shell脚本，退出码为最后一个命令的退出码（即 $?） 
	exit -1
}

# etrap “commands” EXIT ==> 捕捉EXIT脚本退出事件，退出前执行commands命令
# 退出前执行commands指定的命令
# EXIT：在shell退出前执行trap设置的命令，也可以指定为0
# RETURN：在函数返回时，或者.和source执行其他脚本返回时，执行trap设置的命令
# DEBUG：在任何命令执行前执行trap设置的命令，但对于函数仅在函数的第一条命令前执行一次
# ERR：在命令结果为非0时，执行trap设置的命令
# HUP(1)挂起，通常因终端掉线或用户退出而引发
# INT(2)中断，通常因按下Ctrl+C组合键而引发
# QUIT(3)退出，通常因按下Ctrl+组合键而引发
# ABRT(6)中止，通常因某些严重的执行错误而引发
# ALRM(14)报警，通常用来处理超时
# TERM(15)终止，通常在系统关机时发送
trap finish ERR

# $# 传递给脚本或函数的参数个数 ==> ./build/mk-kernel.sh rockpi4b ==> 1
if [ $# != 1 ]; then
	BOARD=rk3288-evb
fi

# https://blog.csdn.net/anqixiang/article/details/111598067
# [ ]是符合POSIX标准的测试语句，兼容性更强，几乎可以运行在所有的Shell解释器中
# [[ ]]仅可运行在特定的几个Shell解释器中(如Bash等)
# [ ]中使用-a和-o表示逻辑与和逻辑或，[[ ]]使用&&和||来表示
# command1 && command2  ==>  &&左边的命令（命令1）返回真(即返回0，成功被执行）后，&&右边的命令（命令2）才能够被执行；换句话说，“如果这个命令执行成功&&那么执行这个命令”
# 命令之间使用 && 连接，实现逻辑与的功能。只有在 && 左边的命令返回真（命令返回值 $? == 0），&& 右边的命令才会被执行;只要有一个命令返回假（命令返回值 $? == 1），后面的命令就不会被执行
# command1 || command2 ==> ||则与&&相反。如果||左边的命令（command1）未执行成功，那么就执行||右边的命令（command2）；或者换句话说，“如果这个命令执行失败了||那么就执行这个命令。 
# 只要有一个命令返回真（命令返回值 $? == 0），后面的命令就不会被执行。
# 只有在 || 左边的命令返回假（命令返回值 $? == 1），|| 右边的命令才会被执行。这和 c 语言中的逻辑或语法功能相同，即实现短路逻辑或操作。
[ ! -d ${OUT} ] && mkdir ${OUT}
[ ! -d ${OUT}/kernel ] && mkdir ${OUT}/kernel

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

# $?表示显示最后命令的退出状态。0表示没有错误，其他任何值表明有错误。这可以用来用作流程控制
# $? 不等于0的话就退出
if [ $? -ne 0 ]; then
	exit
fi

echo -e "\e[36m Building kernel for ${BOARD} board! \e[0m"

# make kernelversion ==> 在内核的编译源码树中执行这条语句，会打印出当前的源码树的版本信息 ==> make kernelversion ==> 4.4.154
KERNEL_VERSION=$(cd ${LOCALPATH}/kernel && make kernelversion)
echo $KERNEL_VERSION

# 这里用"4.5"的作用是以"4.5"为版本分割线，version_gt 中会把version_gt的参数做自然数的顺序排序，所以"4.5"为版本分割线，
# "4.5"及以下的版本,${KERNEL_VERSION}在前，${KERNEL_VERSION} == $1(${KERNEL_VERSION})，所以version_gt中返回假，就不走下面的分支，
# "4.5"  以上的版本,"4.5"在前，"4.5" != $1(${KERNEL_VERSION})，所以version_gt中返回真，就走下面的分支，
if version_gt "${KERNEL_VERSION}"   "4.5"; then   #4.5以及以下的版本，不走下面的赋值语句
# ${DTB_MAINLINE}不为空的时候，将${DTB_MAINLINE}的值赋给 DTB  ==> 
# ${DEFCONFIG_MAINLINE}不为空的时候，将${DEFCONFIG_MAINLINE}的值赋给 DEFCONFIG
	if [ "${DTB_MAINLINE}" ]; then        # 4.5以上的版本==> board_configs.sh ==> DTB_MAINLINE=rk3399-rock-pi-4.dtb
		DTB=${DTB_MAINLINE}               # 4.5以上的版本==> DTB=rk3399-rock-pi-4.dtb
	fi
	if [ "${DEFCONFIG_MAINLINE}" ]; then  # 4.5以上的版本==> board_configs.sh ==> DEFCONFIG_MAINLINE=defconfig
		DEFCONFIG=${DEFCONFIG_MAINLINE}   # 4.5以上的版本==> DEFCONFIG=defconfig
	fi
fi


# 4.5及下的版本==> DTB=rrk3399-rock-pi-4b.dtb
# 4.5及下的版本==> DEFCONFIG=rockchip_linux_defconfig

# 4.5以上的版本==> DTB=rk3399-rock-pi-4.dtb
# 4.5以上的版本==> DEFCONFIG=defconfig

# [ ! -e .config ] ==> kernel目录下没有.config文件时，则执行后面的语句  
# echo -e "\e[36m Using ${DEFCONFIG} \e[0m"
# make ${DEFCONFIG} ==> make rockchip_linux_defconfig ==> 打印如下
#      Using rockchip_linux_defconfig 
#
#      configuration written to .config
#
cd ${LOCALPATH}/kernel
[ ! -e .config ] && echo -e "\e[36m Using ${DEFCONFIG} \e[0m" && make ${DEFCONFIG}

# 开始编译内核
make -j8
cd ${LOCALPATH}

# 编译完后 拷贝内核与dts 到 out目录 
if [ "${ARCH}" == "arm" ]; then
	cp ${LOCALPATH}/kernel/arch/arm/boot/zImage ${OUT}/kernel/
	cp ${LOCALPATH}/kernel/arch/arm/boot/dts/${DTB} ${OUT}/kernel/
else
	cp ${LOCALPATH}/kernel/arch/arm64/boot/Image ${OUT}/kernel/
	cp ${LOCALPATH}/kernel/arch/arm64/boot/dts/rockchip/${DTB} ${OUT}/kernel/
fi

# EXTLINUXPATH     ==> /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux
# board_configs.sh ==> CHIP="rk3399"
# sed -e s,fdt .*,fdt /rk3399-rock-pi-4b.dtb,g -i /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux/rk3399.conf
# Change extlinux.conf according board
# -i：用 sed 的修改结果直接修改读取数据的文件，而不是由屏幕输出动作；
# s：字符串替换，用一个字符串替换另一个字符串。格式为“行范围s/旧字串/新字串/g”（和Vim中的替换格式类似）；
# 就是将/home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux/rk3399.conf 中的"fdt " 替换为 “fdt /rk3399-rock-pi-4b.dtb”
# cat /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/build/extlinux/rk3399.conf 的内容如下
# label kernel-4.4
#     kernel /Image
#     fdt /rk3399-rock-pi-4b.dtb
#     append earlycon=uart8250,mmio32,0xff1a0000 swiotlb=1 coherent_pool=1m earlyprintk console=ttyS2,1500000n8 rw root=PARTUUID=b921b045-1d rootfstype=ext4 init=/sbin/init rootwait
sed -e "s,fdt .*,fdt /$DTB,g" \
	-i ${EXTLINUXPATH}/${CHIP}.conf

# 镜像打包
# ./build/mk-image.sh -c rk3399 -t boot -b rockpi4b
./build/mk-image.sh -c ${CHIP} -t boot -b ${BOARD}

echo -e "\e[36m Kernel build success! \e[0m"
