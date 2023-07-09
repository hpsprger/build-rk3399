#!/bin/bash 

echo "copy my ko start..."
echo "copy rockpi4b_ko_for_testing_kernel.ko"
cp  -f /home/hpsp/rock_space/my_code_wheels/my_code_wheels/fast_ko/kernel_code/rockpi4b_ko/rockpi4b_ko_for_testing_kernel.ko   /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/rootfs/binary/home/linaro 
cp  -f /home/hpsp/rock_space/ethtool/ethtool/ethtool    
ls  -alh /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/rootfs/binary/home/linaro                                                                       /home/hpsp/rock_space/rockpi_4b/rockchip-bsp/rootfs/binary/home/linaro 
echo "copy my ko end..."