#!/usr/bin/env bash

show_usage() {
    echo "Usage: $0 [--prod] [-h/--help] [-s/--skip-output]"
    echo "Builds the CentOS image inside Docker and outputs"
    echo "the result to the binded output directory."
    echo ""
    echo "Installs the CentOs rootfs, installs packages in the created rootfs, creates"
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

# Get the version of the CentOS-7 diskless builder used for this
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
if [ ! -d "/centos7-builder" ]; then
  echo "centos7-builder Docker volume not found. Configure the container with this volume."
  exit 2
fi

# Create diskless-root directory inside the Docker volume, if needed
if [ ! -d "/centos7-builder/diskless-root" ]; then
  mkdir /centos7-builder/diskless-root
fi

cd /centos7-builder

# Download centos-release, if needed
if [ ! -f "centos-release-7-9.2009.0.el7.centos.x86_64.rpm" ]; then
  # Get the centos-release RPM
  #yumdownloader centos-release-7-9.2009.1.el7.centos
  wget ftp.cs.stanford.edu/centos/centos/7/os/x86_64/Packages/centos-release-7-9.2009.0.el7.centos.x86_64.rpm
fi

# centos-release contains things like the yum configs, and is necessary to bootstrap the system
rpm --root=/centos7-builder/diskless-root -ivh --nodeps centos-release-7-9.2009.0.el7.centos.x86_64.rpm
ls /centos7-builder/diskless-root #/etc/yum.repos.d/
# Switch to Stanford mirrors now that mirror.centos.org is offline
sed -i s,mirror.centos.org,mirror.stanford.edu,g /centos7-builder/diskless-root/etc/yum.repos.d/CentOS-*.repo
sed -i s,^#.*baseurl=http,baseurl=http,g /centos7-builder/diskless-root/etc/yum.repos.d/CentOS-*.repo
sed -i s,^mirrorlist=http,#mirrorlist=http,g /centos7-builder/diskless-root/etc/yum.repos.d/CentOS-*.repo

# Add Intel network card drivers for Dell R750 servers
RPMs="./Intel_LAN_drivers_Dell_R750/*.rpm"
for f in $RPMs
do
  echo "Installing $f package...";
  rpm --root=/centos7-builder/diskless-root -ivh --nodeps $f;
done

# Install packages in our target root directory
yum --installroot=/centos7-builder/diskless-root -y install \
    basesystem \
    filesystem \
    bash \
    kernel \
    passwd \
    openssh-server \
    openssh-clients \
    nfs-utils \
    dhcp \
    dhclient \
    net-tools \
    ethtool \
    pciutils \
    usbutils \
    vim \
    NetworkManager \
    screen \
    ipmitool \
    gdb \
    gdb-gdbserver \
    tcpdump \
    ntp \
	sudo \
    yum-cron \
    cronie 

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

# Set some important configuration
if [ ! -e "init" ]; then
  ln -s ./sbin/init ./init
fi
echo NETWORKING=yes > etc/sysconfig/network

# For AFS in dev and NFS in prod
if [ -n "$prod_flag" ]; then
  # Delete usr/local/ contents as prod uses it as mounting point
  # and CentOs 7 has it only with empty directories.
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
# Deactivate all NICs that are disconnected from a network.
# Activate NTP, generate required locales
chroot . \
    bash -c '\
        /root/scripts/create-users.sh && \
        systemctl enable /usr/lib/systemd/system/run_bootfile.service && \
        systemctl enable ntpd && \
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
    fs_filename="CentOs7_Lite_prod_${version}_fs.cpio.gz";
  else
    fs_filename="CentOs7_Lite_dev_${version}_fs.cpio.gz";
  fi

  # Generate the cpio image. Compress with -1 equals to fastest and less compression.
  # This helps with the speed of generating the image and also uncompressing during the PXE boot.
  find | cpio -ocv | pigz -1 > /output/$fs_filename

  # Copy the kernel image
  cp boot/vmlinuz-* /output/
fi
