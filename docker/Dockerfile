FROM centos:7

# As of July 1st, 2024, mirrorlist.centos.org is gone and we need to switch to vault.centos.org
RUN sed -i s,mirror.centos.org,vault.centos.org,g /etc/yum.repos.d/CentOS-*.repo; \
    sed -i s,^#.*baseurl=http,baseurl=http,g /etc/yum.repos.d/CentOS-*.repo; \
    sed -i s,^mirrorlist=http,#mirrorlist=http,g /etc/yum.repos.d/CentOS-*.repo

# Install packages we will need in our 'builder' OS.
# NOTE: Default ulimit is insanely high and causes yum to slow to a crawl
RUN ulimit -n 1024 && \
    yum -y update && \
    yum install -y \
        wget \
        yumdownloader \
        pigz \
	openssh-server \
    && yum clean all -y
