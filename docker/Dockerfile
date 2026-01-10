FROM rockylinux:9

# Install packages we will need in our 'builder' OS
# NOTE: Default ulimit is insanely high and causes yum to slow to a crawl
RUN ulimit -n 1024 && \
    yum -y update && \
    yum install -y \
        wget \
        pigz \
        cpio \
        openssh-server \
        && yum clean all -y