#!/usr/bin/env bash

show_usage() {
    echo "Usage: $0 [--prod] [-h/--help] [-s/--skip-output]"
    echo "Builds the Rocky image inside Docker and outputs"
    echo "the result to the binded output directory."
    echo ""
    echo "Installs the Rocky rootfs, installs packages in the created rootfs, creates"
    echo "user groups and accounts, copy files from the external world to the rootfs,"
    echo "configure services, and export images."
    echo "If --prod is not passed as argument, the image will be built for Dev environment."
    echo ""
    echo "Optional arguments:"
    echo "  -h, --help                  Show this help message and exit"
    echo "  --prod                      Builds image for the production environment"
    echo "  -s, --skip-output           Only builds the image but don't output products. Nice for testing."
    echo ""
    exit
}

prod_flag=
skip_output_flag=

# Create the directory
mkdir -p /rl9-builder/diskless-root/etc/yum.repos.d

cat > /rl9-builder/diskless-root/etc/yum.repos.d/rocky-vault.repo << 'EOF'
[rocky-vault]
name=Rocky Linux Vault
baseurl=https://dl.rockylinux.org/vault/rocky/9.5/BaseOS/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
EOF

dnf --showduplicates list kernel

# Get the version of the Rocky diskless builder used for this
read -r version < VERSION

while [ -n "$1" ]; do
    case "$1" in
        -h | --help)
            # Show this help message and exit
            show_usage
            exit
            ;;
        --prod)
            # Build for prod environment
            prod_flag=1
            ;;
        -s | --skip-output)
            skip_output_flag=1
            ;;
        *)
            # Reject invalid flags
            echo "Error: invalid option $1"
            show_usage
            exit
    esac
    shift
done


# Verify if Docker volume was created. If not, exit script.
if [ ! -d "/rl9-builder" ]; then
  echo "rl9-builder Docker volume not found. Configure the container with this volume."
  exit 2
fi

# Create diskless-root directory inside the Docker volume, if needed
if [ ! -d "/rl9-builder/diskless-root" ]; then
  mkdir /rl9-builder/diskless-root
fi

cd /rl9-builder

# rocky-release contains things like the dnf configs, and is necessary to bootstrap the system
dnf --installroot=/rl9-builder/diskless-root --releasever=9 -y install rocky-release

# Install packages in our target root directory
# --setopt=install_weak_deps=False: Cuts image size by more than half
# --enablerepo=rocky-vault: Used to get specific version of the kernel
dnf --installroot=/rl9-builder/diskless-root  --enablerepo=rocky-vault --setopt=install_weak_deps=False -y install \
    basesystem \
    filesystem \
    bash \
    kernel-5.14.0-503.16.1.el9_5 \
    passwd \
    openssh-server \
    openssh-clients \
    nfs-utils \
    dhcp-client \
    dhclient \
    net-tools \
    ethtool \
    pciutils \
    usbutils \
    vim \
    NetworkManager \
    tmux \
    ipmitool \
    gdb \
    gdb-gdbserver \
    tcpdump \
    chrony \
	  sudo \
    cronie \
    hostname \
    less \
    glibc-locale-source

# hack alert! Install screen on host to work around a bug:
#   gpg key read from /etc/pki/... but rpm WILL NOT APPEND "installroot" to path
dnf -y install epel-release
dnf -y install screen
# for the screen cli utility only
dnf --installroot=/rl9-builder/diskless-root --releasever=9 -y install epel-release
dnf --installroot=/rl9-builder/diskless-root  -y install screen

# Go to our target root directory
cd diskless-root

# Add SLAC custom files and force copy, even if it exists
cp -r /custom_files/slac.sh etc/profile.d/
if [ ! -d "root/scripts" ]; then
  mkdir -p root/scripts
fi
cp -r /custom_files/run_bootfile_dev.sh root/scripts
cp -r /custom_files/run_bootfile_prod.sh root/scripts
cp -r /custom_files/create-users.sh root/scripts
cp -r /custom_files/disable_disconnected_nics.sh root/scripts
cp -r /custom_files/disable_disconnected_nics.service usr/lib/systemd/system/
if [ -n "$prod_flag" ]; then
  cp -r /custom_files/run_bootfile_prod.service usr/lib/systemd/system/run_bootfile.service
else
  cp -r /custom_files/run_bootfile_dev.service usr/lib/systemd/system/run_bootfile.service
fi
cp -r /custom_files/epics.conf etc/security/limits.d
cp -r /custom_files/90-nproc.conf etc/security/limits.d
cp -r /custom_files/SLAC_properties etc/SLAC_properties
cp -r /custom_files/sudoers etc/sudoers
cp -f /custom_files/sshd_config etc/ssh/sshd_config
cp -f /custom_files/limits.conf etc/security/limits.conf
cp -f /custom_files/udev_rules/* etc/udev/rules.d/

# Set some important configuration
if [ ! -e "init" ]; then
  ln -s ./sbin/init ./init
fi
echo NETWORKING=yes > etc/sysconfig/network

# For AFS in dev and NFS in prod
if [ -n "$prod_flag" ]; then
  # Delete usr/local/ contents as prod uses it as mounting point
  # and Rocky has only empty directories under /usr/local.
  rm -rf usr/local/*
  if [ -d "afs/slac.stanford.edu" ]; then
    rm -rf afs
  fi
  echo "mccfs2:/export/mccfs/usr/local /usr/local nfs ro,nolock,noac,soft 0 0" > etc/fstab
else
  if [ ! -d "afs/slac.stanford.edu" ]; then
    mkdir -p afs/slac.stanford.edu
  fi
  if [ -d "afs/slac.stanford.edu" ]; then
    # device  mountpoint  fstype  options  dump  pass
    echo "s3dflclsdevnfs001:/sdf/group/ad/transition/afs/slac.stanford.edu /afs/slac.stanford.edu nfs _netdev,auto,x-systemd.automount,x-systemd.mount-timeout=5min,x-systemd.after=sys-subsystem-net-devices-enp7s0.device,retry=10,timeo=14 0 0" > etc/fstab
  fi
fi

# Allow laci to access without password and blocks root ssh login
sed -i "s/#PermitEmptyPasswords no/PermitEmptyPasswords yes/" etc/ssh/sshd_config
sed -i "s/#PermitRootLogin yes/PermitRootLogin no/" etc/ssh/sshd_config

# Increasing limit priorities for EPICS IOCs to set SCHED_FIFO properly
sed -i "s/#DefaultLimitMEMLOCK=/DefaultLimitMEMLOCK=infinity/g" etc/systemd/system.conf
sed -i "s/#DefaultLimitRTPRIO=/DefaultLimitRTPRIO=infinity/g" etc/systemd/system.conf
sed -i "s/#DefaultLimitMEMLOCK=/DefaultLimitMEMLOCK=infinity/g" etc/systemd/user.conf
sed -i "s/#DefaultLimitRTPRIO=/DefaultLimitRTPRIO=infinity/g" etc/systemd/user.conf

# chroot, set a blank password to root, and create the laci account. laci
# account must have UID 8412 and be part of an lcls group with GID 2211.
# The IDs are important for accessing NFS directories.
# Activate NTP.
chroot . \
    bash -c '\
        /root/scripts/create-users.sh && \
        systemctl enable /usr/lib/systemd/system/run_bootfile.service && \
	      systemctl enable chronyd && \
        systemctl enable disable_disconnected_nics.service && \
        localedef -i en_US -f UTF-8 en_US.utf8 && \
        exit \
    '

# Set the default locale. This matches the default on our DEV machines.
echo "LANG=en_US.utf8" > etc/locale.conf


# Generate ssh keys to avoid generating new ones every time the diskless
# system boots, creating annoying RSA key mismatch error messages when
# an user wants to connect.
/usr/bin/ssh-keygen -A
cp -f /etc/ssh/*key* etc/ssh

if [ -z "$skip_output_flag" ]; then
  if [ -n "$prod_flag" ]; then
    fs_filename="Rocky9_Lite_prod_${version}_fs.cpio.gz";
  else
    fs_filename="Rocky9_Lite_dev_${version}_fs.cpio.gz";
  fi

  # Generate the cpio image. Compress with -1 equals to fastest and less compression.
  # This helps with the speed of generating the image and also uncompressing during the PXE boot.
  find | cpio -ocv | pigz -1 > /output/$fs_filename

  # Copy the kernel image
  kvers="`basename /rl9-builder/diskless-root/lib/modules/*`"
  cp /rl9-builder/diskless-root/lib/modules/$kvers/vmlinuz /rl9-builder/diskless-root/boot/vmlinuz-$kvers
  cp  /rl9-builder/diskless-root/lib/modules/$kvers/vmlinuz /output/vmlinuz-$kvers
fi
