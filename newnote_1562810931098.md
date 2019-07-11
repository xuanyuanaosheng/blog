## LVM小知识

### 参考文档
- https://blog.51cto.com/anyisalin/1748342
- https://blog.51cto.com/woyaoxuelinux/1973718

1. 默认测试环境测试机的状态：

- 4核8G
- lvm2

2. LVM(Logical Volume Manager)：逻辑卷管理相关的命令
```
vg管理工具：
    vgs    #查看vg简要信息
    vgdisplay      #查看vg详细信息
    vgcreate  [-s #[kKmMgGtTpPeE]] VolumeGroupName  PhysicalDevicePath [PhysicalDevicePath...]    #创建vg
    vgextend  VolumeGroupName  PhysicalDevicePath [PhysicalDevicePath...]    #扩展vg容量
    vgreduce  VolumeGroupName  PhysicalDevicePath [PhysicalDevicePath...]    #缩减vg容量
    vgremove  VolumeGroupName  #删除vg

lv管理工具：
    lvs    #查看lv简要信息
    lvdisplay    #查看lv详细信息
    lvcreate -L #[mMgGtT] -n NAME VolumeGroup    #创建lv
    lvremove /dev/VG_NAME/LV_NAME    #删除lv

扩展逻辑卷：
    lvextend -L [+]#[mMgGtT] /dev/VG_NAME/LV_NAME    #扩展逻辑卷
    resize2fs /dev/VG_NAME/LV_NAME    #重新定义文件系统大小
    
缩减逻辑卷：
    umount /dev/VG_NAME/LV_NAME    #卸载lv
    e2fsck -f /dev/VG_NAME/LV_NAME    #检查lv
    resize2fs /dev/VG_NAME/LV_NAME #[mMgGtT]    #重新定义lv大小
    lvreduce -L [-] [mMgGtT] /dev/VG_NAME/LV_NAME    #缩减lv
```

3. 系统环境查看
```
通过fdisk -l 命令查看当前系统的磁盘信息

TEST [root@nscnvx505 current]# fdisk -l

Disk /dev/sdb: 128.8 GB, 128849018880 bytes, 251658240 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/sda: 1073 MB, 1073741824 bytes, 2097152 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x0003d37d

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048     1026047      512000   83  Linux

Disk /dev/mapper/vg00-root: 5368 MB, 5368709120 bytes, 10485760 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/vg00-swap: 4294 MB, 4294967296 bytes, 8388608 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/vg00-opt: 2147 MB, 2147483648 bytes, 4194304 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/vg00-tmp: 5368 MB, 5368709120 bytes, 10485760 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/vg00-var: 47.2 GB, 47244640256 bytes, 92274688 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/vg00-home: 1073 MB, 1073741824 bytes, 2097152 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes

```


4. LVM扩展
```
[root@server2 ~]# vgextend myvg /dev/sdc    #扩展myvg，将sdc的空间也提供给myvg
  Volume group "myvg" successfully extended
  
[root@server2 ~]# vgs    #查看vg当前信息，myvg大小为40G
  VG   #PV #LV #SN Attr   VSize  VFree 
  myvg   2   1   0 wz--n- 39.99g 29.99g
  
[root@server2 ~]# umount /mnt/    #卸载mylv

[root@server2 ~]# lvextend -L 30G /dev/myvg/mylv     #扩展lv到30G
  Size of logical volume myvg/mylv changed from 10.00 GiB (2560 extents) to 30.00 GiB (7680 extents).
  Logical volume mylv successfully resized
  
[root@server2 ~]# lvs    #查看当前lv信息，mylv为30G
  LV   VG   Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  mylv myvg -wi-a----- 30.00g 
[root@server2 ~]# mount /dev/mapper/myvg-mylv /mnt/    #挂载mylv到/mnt目录

[root@server2 ~]# df    ##注意：这里显示mylv大小只有10G，这是因为我们没有进行重新定义
Filesystem           1K-blocks    Used Available Use% Mounted on
/dev/sda2             15357672 3527844  11043048  25% /
tmpfs                   502384       0    502384   0% /dev/shm
/dev/sda1               198123   36589    151094  20% /boot
/dev/mapper/myvg-mylv
                      10190136   23028   9642820   1% /mnt
[root@server2 ~]# df -lh
Filesystem            Size  Used Avail Use% Mounted on
/dev/sda2              15G  3.4G   11G  25% /
tmpfs                 491M     0  491M   0% /dev/shm
/dev/sda1             194M   36M  148M  20% /boot
/dev/mapper/myvg-mylv
                      9.8G   23M  9.2G   1% /mnt
                      
[root@server2 ~]# resize2fs /dev/mapper/myvg-mylv     #使用resize2fs可以重新定义分区的大小
resize2fs 1.41.12 (17-May-2010)
Filesystem at /dev/mapper/myvg-mylv is mounted on /mnt; on-line resizing required
old desc_blocks = 1, new_desc_blocks = 2
Performing an on-line resize of /dev/mapper/myvg-mylv to 7864320 (4k) blocks.
The filesystem on /dev/mapper/myvg-mylv is now 7864320 blocks long.
[root@server2 ~]# df -lh    #现在mylv大小终于恢复正常了
Filesystem            Size  Used Avail Use% Mounted on
/dev/sda2              15G  3.4G   11G  25% /
tmpfs                 491M     0  491M   0% /dev/shm
/dev/sda1             194M   36M  148M  20% /boot
/dev/mapper/myvg-mylv
                       30G   28M   28G   1% /mnt
```






