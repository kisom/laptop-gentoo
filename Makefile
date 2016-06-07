#
#                _        _    ____ _____ ___  ____  
#               | |      / \  |  _ \_   _/ _ \|  _ \
#               | |     / _ \ | |_) || || | | | |_) |
#               | |___ / ___ \|  __/ | || |_| |  __/ 
#               |_____/_/   \_\_|    |_| \___/|_|    
#                                                    
#                  ____ _____ _   _ _____ ___   ___  
#                 / ___| ____| \ | |_   _/ _ \ / _ \
#                | |  _|  _| |  \| | | || | | | | | |
#                | |_| | |___| |\  | | || |_| | |_| |
#                 \____|_____|_| \_| |_| \___/ \___/ 
#                                                    
#
# I've had it with Debian. The only ways to get a grsec kernel are to
# build my own kernel (I have better things to do) or to use
# testing. However, the last three upgrades have broken my system
# (thanks, Poettering!) I decided to build my base platform looking
# for a few key features:
#
#   + I want a grsec kernel.
#   + I'd like a fairly minimal base image. Most of what I need to do,
#     I have to use a VM that's set up to more closely match production.
#   + I don't want systemd; I'll probably stick to OpenRC because it's
#     known good and doesn't try to do too much. I don't want to get
#     dragged into the systemd flamewar circlejerk --I have better
#     things to expend emotional energy on than software. This being
#     said, I gave it a shot, and while I generally like the interface
#     and the things it promises to do, it consistently fails to
#     deliver on those promises while managing to render my system
#     unbootable or unusable an unacceptable number of times. Also,
#     given my experiences with this and their other software, I don't
#     trust the Poettering / Lunix / FreeDesktop crowd to build
#     secure, reliable software. This is my work laptop, it needs to
#     work. I can't just screw around with it and leave it half-broken
#     for weeks on end like I do with my personal laptop.
#   + I really want a system where I don't have to think a whole lot
#     about maintaining it. This means standard Unix tools; I'd like
#     to avoid the Lunix trainwreck.
#   + I want to use Salt to manage my laptop. There are a number of
#     solutions in this space, but I'm going with Salt because it's
#     extensible in a language I know (even if I'm not a huge fan of
#     the language) and because it doesn't require SSH for everything
#     (e.g. Ansible).
#
# I gave Alpine a shot, but I couldn't get the image to boot on my
# T460s, despite an attempt at patching the installer and doing
# various things with it. Furthermore, the base image doesn't include
# FDE (WTAF?), so I had to try to tinker with the initramfs and still
# couldn't get it boot. After a few days, I'm calling it quits.
#
# Unfortunately, the list of well-supported distributions that meet
# the above criteria is short. The old adage rings true --if you
# want something done right, you have to do it yourself. So, with
# great reluctance, I'm going with Gentoo.
#
# Believe me, the last thing I want to do is have to waste more time
# setting up Linux, and I would *love* it if Debian had worked
# out. But, here we are, and at least it still beats using OS X.
#
# This started life as a set of scripts for Alpine that I'm now using
# to build Gentoo. The goal is to build a root file system and
# installer that can be quickly restored so I don't have to screw
# around too much with the installer.
#
# As the gladiators in ancient Rome used to say, "Ave, Imperator, nos
# Gentoo te salutamus."
#
########################################################################

#                          ____  _   _ ___ _     ____
#                         | __ )| | | |_ _| |   |  _ \
#                         |  _ \| | | || || |   | | | |
#                         | |_) | |_| || || |___| |_| |
#                         |____/ \___/|___|_____|____/ 
#                                                      
#            __     ___    ____  ___    _    ____  _     _____ ____  
#            \ \   / / \  |  _ \|_ _|  / \  | __ )| |   | ____/ ___| 
#             \ \ / / _ \ | |_) || |  / _ \ |  _ \| |   |  _| \___ \
#              \ V / ___ \|  _ < | | / ___ \| |_) | |___| |___ ___) |
#               \_/_/   \_\_| \_\___/_/   \_\____/|_____|_____|____/ 
# 

# Which release are we using?
RELEASE :=		20160526
WORKING :=		gentoo

# Where can we fetch the release?
UPSTREAM_URL :=		https://p.kyleisom.net/gentoo

# Which iso are we using?
UPSTREAM_ISO :=		install-amd64-minimal-$(RELEASE).iso
OUTPUT_ISO :=		gentoo-$(RELEASE).iso

# Which stage3 are we using?
STAGE3 :=		stage3-amd64-hardened-$(RELEASE).tar.bz2

# Where are the squashfs images?
UPSTREAM_SQUASHFS :=	$(RELEASE)/image.squashfs
WORKING_SQUASHFS :=	gentoo/image.squashfs

# Where should the squashfs images be unpacked?
UPSTREAM_ROOTFS :=	$(RELEASE)-rootfs
WORKING_ROOTFS :=	gentoo-rootfs

# What patches should be applied to the rootfs?
PATCHDIR :=		patches
PATCHFILES :=

# Who's the current user?
WHOAMI :=		$(USER)
WHOAMI ?=		$(LOGNAME)
WHOAMI ?=		$(USERNAME)

# What's the {iso,sys}linux hybrid MBR? I kept mistyping this; this
# keeps errors from creeping in. There are both an isohdpfx.bin and a
# isohdppx.bin file in the upstream source; ppx boots from a partition
# device while pfx boots from a raw device.
HYBRIDBIN :=	isohdpfx.bin


########################################################################
#                   _____  _    ____   ____ _____ _____ ____
#                  |_   _|/ \  |  _ \ / ___| ____|_   _/ ___| 
#                    | | / _ \ | |_) | |  _|  _|   | | \___ \
#                    | |/ ___ \|  _ <| |_| | |___  | |  ___) |
#                    |_/_/   \_\_| \_\\____|_____| |_| |____/
#
# (may your aim be ever true, and try not to shoot yourself in the
# damn foot)
#
# N.B. some of these targets need sudo access. Where this is required,
# the target should echo the command being run beforehand.
#
# The targets are divided into two stages: those relating to building
# the ISO itself, and those relating to building the live CD rootfs.

# Default action is to build the rootfs and build the iso.
.PHONY: all
all: build-rootfs build-iso

# useful, but a GNU makeism
show-%: ; @echo $*=$($*)

clean-file-%: ; ( [ ! -z "$*" -a -e "$*" ] && rm -f "$*" )
clean-dir-%: ; ( [ ! -z "$*" -a -d "$*" ] && rm -fr "$*" )

# fetch upstreams and make sure the originals are okay
upstream/$(UPSTREAM_ISO) upstream/$(STAGE3):
	curl -L $(UPSTREAM_URL)/upstream.tbz | tar xjf

.PHONY: integrity-check
integrity-check: upstream/$(UPSTREAM_ISO) upstream/$(STAGE3)
	@sha256sum -c upstream/$(UPSTREAM_ISO).SHA256
	@sha256sum -c upstream/$(STAGE3).SHA256

.PHONY: upstream working
upstream: integrity-check $(RELEASE) upstream-rootfs
working: upstream $(WORKING) $(WORKING_ROOTFS)

# clean removes the working copies of things. dist-clean removes
# everything that can't be regenerated.
.PHONY: clean dist-clean clean-upstream clean-working
clean: clean-working
dist-clean: clean-working clean-upstream
	rm -f upstream/$(UPSTREAM_ISO)
	rm -f upstream/$(STAGE3)
	rm -f upstream/linux-firmware.tbz

clean-upstream:
	-sudo rm -r $(UPSTREAM_ROOTFS)
	-sudo rm -r $(RELEASE)

clean-working:
	-sudo rm -r $(WORKING_ROOTFS)
	-sudo rm -r $(WORKING)
	-rm -f $(OUTPUT_ISO)

# The release directory is unpacked with the provided script, which is
# better than sticking a bunch of stuff in the Makefile.
$(RELEASE):
	scripts/unpack-iso

$(WORKING): $(RELEASE)
	rsync -auq $(RELEASE)/ $(WORKING)/

#-----------------------------------------------------------------------
#                                ___ ____   ___  
#                               |_ _/ ___| / _ \
#                                | |\___ \| | | |
#                                | | ___) | |_| |
#                               |___|____/ \___/ 
#                                                
# These parts are concerned with generating the ISO itself.

# hybridbin copies over the HybridISO MBR from the isolinux sources.
.PHONY: hybridbin
hybridbin: $(WORKING)/isolinux/$(HYBRIDBIN)

$(WORKING)/isolinux/$(HYBRIDBIN): $(WORKING) upstream/$(HYBRIDBIN)
	rsync -auq upstream/$(HYBRIDBIN) $@

.PHONY: build-iso
build-iso: $(OUTPUT_ISO)

# The ISO is generated as a HybridISO using the xorriso tools. In
# mkisofs mode (e.g. the -as flag), xorriso takes the same args as
# mkisofs. Since future you is probably too lazy to look through this
# and hopefully has better things to do than figure this stuff out
# *again*, here's a glossary and a cheat sheet:
#
#   Joliet: Microsoft's extension to iso9660, providing support for
#       long file names in the image. Which is cool, because this
#       isn't 1988. Probably don't really need to add Joliet support,
#       but it wouldn't surprise me if UEFI wanted it.
#   Rock Ridge: Another extension is iso9660, provides POSIX file
#       system semantics.
#
#
#   -r                  Sets up Rock Ridge records. You could use -R,
#                       but with -r "file ownership and modes are set
#                       to more useful values."
#   -J                  Generate Joliet directory records.
#   -joliet-long        Support even longer Joliet filenames.
#   -v                  Surprisingly, this does what you think it does.
#   -isohybrid-mbr      The HybridISO MBR. Right. You get this from the
#                       syslinux/isolinux project. See the HYBRIDISO
#                       variable and the hybridiso target.
#   -partition_offset   This is an xorriso option. From the man page: "A
#                       non-zero partition offset causes two
#                       superblocks to be generated and two sets of
#                       directory trees." 16 is the minimum value, and this
#                       is counted in 2048 byte blocks.
#   -b                  Path (relative to the ISO's root file system) to an
#                       El Torito boot image, the closely related but far
#                       less tasty cousin to the El Dorito. Honestly, it's
#                       somewhat of a disappointment to the family.
#   -c                  Path (also relative to the ISO's root file system) to
#                       an El Torito boot catalog.
#   -no-emul-boot       c.f. youtu.be/mT0Jm8fsuQY. No disk emulation is done.
#   -boot-load-size     Number of virtual 512 byte disk sectors to load; man
#                       page notes possible compatibility problems where this
#                       isn't a multiple of 4.
#   -boot-info-table    Patch in a "56-byte with information of the CD-ROM
#                       layout... patched in at offset 8 in the boot file."
#   -o                  Also, amazingly, does what you think it does.
#
# The isohybrid tool ships with xorriso and does some manipulation on
# an ISO to make it hybridable, or so it claims.
$(OUTPUT_ISO): $(WORKING) hybridbin
	xorriso -as mkisofs -r -J -joliet-long -v -v			\
		-A $(RELEASE)						\
		-isohybrid-mbr $(WORKING)/isolinux/$(HYBRIDBIN)		\
		-partition_offset 16					\
		-b isolinux/isolinux.bin				\
		-c isolinux/boot.cat					\
	 	-no-emul-boot -boot-load-size 4 -boot-info-table 	\
		-o "$(OUTPUT_ISO)" $(WORKING) && isohybrid $(OUTPUT_ISO)

# Install is intended to write the generated ISO to a flash drive. To
# use it, a DEV variable has to be provided to make pointing at the
# device to use.
# 
# No sanity checking on the device is provided: ¯\_(ツ)_/¯
.PHONY: install
install:
	@if [ -z "$(DEV)" ];						\
	then								\
		echo "[!] DEV is empty! (make DEV=/dev/XXX)";		\
		exit 1;							\
	fi
	sudo dd if=$(OUTPUT_ISO) of=$(DEV) $(DDFLAGS)


#-----------------------------------------------------------------------
#	    ____   ___	_   _	_    ____  _   _ _____ ____  
#	   / ___| / _ \| | | | / \  / ___|| | | |  ___/ ___| 
#	   \___ \| | | | | | |/ _ \ \___ \| |_| | |_  \___ \
#	    ___) | |_| | |_| / ___ \ ___) |  _	|  _|  ___) |
#	   |____/ \__\_\\___/_/	  \_\____/|_| |_|_|   |____/ 
#							     

$(UPSTREAM_SQUASHFS): $(RELEASE)

# Unpack the upstream's root filesystem.
.PHONY: upstream-rootfs
rootfs: $(UPSTREAM_ROOTFS)
$(UPSTREAM_ROOTFS): $(UPSTREAM_SQUASHFS)
	sudo unsquashfs -d $@ $(UPSTREAM_SQUASHFS)

# The working rootfs is initially just a copy of the upstream rootfs.
.PHONY: working-rootfs
working-rootfs: $(WORKING_ROOTFS)
$(WORKING_ROOTFS): $(UPSTREAM_ROOTFS)
	[ ! -d "$@" ] && mkdir $@
	sudo rsync -auq $(UPSTREAM_ROOTFS)/ $@/

# It's useful to have all the firmwares available.
LINUX_FIRMWARE :=	https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
.PHONY: firmware
firmware: upstream/linux-firmware.tbz
upstream/linux-firmware.tbz:
	git clone $(LINUX_FIRMWARE) && 					\
	rm -rf linux-firmware/.git* &&					\
	tar cjf $@ linux-firmware   &&					\
	rm -rf linux-firmware

# Building the rootfs involves copying over the firmware, stage3
# tarball, and install script.
.PHONY: build-rootfs
build-rootfs: $(WORKING_SQUASHFS)
$(WORKING_SQUASHFS): $(WORKING) working-rootfs firmware
	sudo cp upstream/$(STAGE3) $(WORKING_ROOTFS)/$(STAGE3)
	for patchfile in $(PATCHFILES) ;				\
	do								\
		sudo patch -r -p1 < ../$(PATCHDIR)/$$patchfile ;	\
	done
	sudo cp upstream/linux-firmware.tbz $(WORKING_ROOTFS)/
	sudo cp scripts/gentoo-installer $(WORKING_ROOTFS)/
	sudo chmod +x $(WORKING_ROOTFS)/gentoo-installer
	[ -e $(WORKING_SQUASHFS) ] && sudo rm -f $(WORKING_SQUASHFS) || true
	sudo mksquashfs $(WORKING_ROOTFS) $(WORKING_SQUASHFS)
	sudo chown $(WHOAMI):$(WHOAMI) $(WORKING_SQUASHFS)


#=======================================================================
# _____ _       _____ ___ _   _ 
# | ____| |     |  ___|_ _| \ | |
# |  _| | |     | |_   | ||  \| |
# | |___| |___  |  _|  | || |\  |
# |_____|_____| |_|   |___|_| \_|
# 
#  
#              .----.
#            [-|.  .|-]
#            [-|.\/.|-]
#              \||||/
#               ||||
#               ||||
#               ||||
#               ||||
#               ||||
#               ||||
#              /||||
#            [-|||||
#              |||||
#              |||||
#              |||||
#              |||||
#            _.|||||._
#         .-'  |||||  `-.
#       .'     |||||     `.
#     .'       |||||       `.
#    /         |||||         \
#   /          |||||          \
#   |          |||||          |
#   |          _____          |
#   |-.       '-----'         |
#   \  `.      |||||          /
#    \   \    .-----.        /
#     `.  \   |     |      .'
#       '.|   '.    |    .'
#         '--._|____|_.-'
#  
# LGB
#
# I'd rather be playing banjo than dealing with another Lunix trash fire...
#-0---5---|-5---5---|-7---7---|-7---7---|-9---7---|-5---0---|-2-------|---------
#---------|-----0---|-----5---|-----5---|---------|---------|-----0---|---------
#---------|-----0---|---------|---------|---------|---------|---------|-2---0---
#---------|---------|---------|---------|---------|---------|---------|---------
#---------|-------0-|-------0-|-------0-|---0---0-|---0---0-|---------|---------
