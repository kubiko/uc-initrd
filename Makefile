DPKG_ARCH := $(shell dpkg --print-architecture)
SUDO := sudo
ENV := $(SUDO) env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANG=C
ifneq (,$(filter amd64 i386,$(DPKG_ARCH)))
UBUNTU_ARCHIVE := http://archive.ubuntu.com/ubuntu
UBUNTU_SECURITY_ARCHIVE := http://security.ubuntu.com/ubuntu
PACKAGES := initramfs-tools-ubuntu-core xz-utils
else
UBUNTU_ARCHIVE := http://ports.ubuntu.com/ubuntu-ports
UBUNTU_SECURITY_ARCHIVE := http://ports.ubuntu.com/ubuntu-ports
PACKAGES := initramfs-tools-ubuntu-core xz-utils systemd
endif

unpacked-initrd = unpacked-initrd
initrd-overlay = initrd-overlay

install: VERSION=$(shell basename chroot/boot/initrd.img-* | cut -c 12- | sed 's/-generic//g')

all: repack-initrd

prepare-chroot:
	$(SUDO) debootstrap --variant=minbase $(RELEASE) chroot

	# setup sources first
	echo "deb $(UBUNTU_ARCHIVE) $(RELEASE) main" | $(SUDO) tee chroot/etc/apt/sources.list
	echo "deb $(UBUNTU_ARCHIVE) $(RELEASE) universe" | $(SUDO) tee -a chroot/etc/apt/sources.list
	echo "deb $(UBUNTU_SECURITY_ARCHIVE) $(RELEASE)-security main" | $(SUDO) tee -a chroot/etc/apt/sources.list

	# first install gnupg
	$(ENV) chroot chroot apt-get -y update
	$(ENV) chroot chroot apt-get -y install gnupg
	# Enable ppa:snappy-dev/image inside of the chroot and add the PPA's
	# public signing key to apt
	cat snappy-dev-image.asc | $(ENV) chroot chroot apt-key add -
	echo "deb http://ppa.launchpad.net/snappy-dev/image/ubuntu $(RELEASE) main" | $(SUDO) tee -a chroot/etc/apt/sources.list

	# install all updates
	$(ENV) chroot chroot apt-get -y update
	$(ENV) chroot chroot apt-get -y upgrade

	$(SUDO) mkdir -p chroot/etc/initramfs-tools/conf.d
	echo "COMPRESS=lzma" | $(SUDO) tee -a chroot/etc/initramfs-tools/conf.d/ubuntu-core.conf
	$(ENV) chroot chroot apt-get -y update
	$(ENV) chroot chroot apt-get -y install $(PACKAGES)
	$(SUDO) mount --bind /proc chroot/proc
	$(SUDO) mount --bind /sys chroot/sys

prepare-kernel: prepare-chroot
	$(ENV) chroot chroot apt-get -y install linux-generic
	$(SUDO) umount chroot/sys
	$(SUDO) umount chroot/proc
	# change permisions so snapcraft can clean later
	$(SUDO) chown $(USER):$(USER) -R .

unpack-initrd: prepare-kernel
	unmkinitramfs chroot/boot/initrd.img-* $(unpacked-initrd)

clean-initrd: unpack-initrd
	# handle case when initrd has microcode
	rm -rf $(unpacked-initrd)/main/lib/firmware
	rm -rf $(unpacked-initrd)/main/lib/modules
	rm -rf $(unpacked-initrd)/lib/firmware
	rm -rf $(unpacked-initrd)/lib/modules

overlay-initrd: unpack-initrd
	# apply overlay, this is mainly now updated resize script
	# handle situation when there is microcode and main initrd is in subdir
	if [ -d $(unpacked-initrd)/main ]; then \
	  cp -r $(initrd-overlay)/* $(unpacked-initrd)/main/; \
	else \
	  cp -r $(initrd-overlay)/* $(unpacked-initrd)/; \
	fi

repack-initrd: clean-initrd overlay-initrd
	cd $(unpacked-initrd);	find . | cpio --create --quiet --format='newc' --owner=0:0 | lz4 -9 -l > ../initrd.img;

install:
	mv initrd.img $(DESTDIR)/initrd.img-$(VERSION)
