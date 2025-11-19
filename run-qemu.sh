#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE=./output/CentOs7_Lite_dev_$(cat VERSION)_fs.cpio.gz
while test $# -gt 0; do
	case $1 in
	--prod)
		IMAGE=./output/CentOs7_Lite_prod_$(cat VERSION)_fs.cpio.gz
		shift
		;;
	*)
		echo "Unknown arg $1"
		exit 1
		;;
	esac
done

qemu-system-x86_64 \
	-m size=2048 \
	-nographic -no-reboot \
	-kernel ./$(find output -iname "vmlinuz-*" | head -n 1) \
	-initrd $IMAGE \
	-append "console=ttyS0 init=/init root=/dev/ram0" \
	-nic user,hostfwd=tcp::8022-:22

