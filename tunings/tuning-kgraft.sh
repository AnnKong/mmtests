#!/bin/bash
# This script manipulates kgraft patches.

. $SHELLPACK_INCLUDE/common.sh

TMPDIR=$(readlink -m $SHELLPACK_TEMP/tuning-kgraft)
mkdir -p $TMPDIR
cd $TMPDIR

export MMTESTS_IGNORE_MIRROR=yes

if [ -z "$KERN_BUILD_DIR" ]; then
	KERN_BUILD_DIR=/lib/modules/$(uname -r)/build/
fi

if [ ! -d "$KERN_BUILD_DIR" ]; then
	die "Current kernel's headers not found at $KERN_BUILD_DIR."
fi

function insert_patch() {
	sources_fetch $PATCH "" patch.tgz
	tar xzf patch.tgz

	# this file must set KGRAFT_MODULE_DIR, KGRAFT_MODULE_NAME and KGRAFT_SYSFS_NAME
	source tuning-kgraft-info.sh || die "Couldn't load patch info"

	if lsmod | grep -q $KGRAFT_MODULE_NAME; then
		die Module $KGRAFT_MODULE_NAME already inserted
	fi

	make -C $KERN_BUILD_DIR M="$TMPDIR/$KGRAFT_MODULE_DIR" O="$TMPDIR/$KGRAFT_MODULE_DIR" || die "Couldn't make the kgraft patch"

	insmod $TMPDIR/$KGRAFT_MODULE_DIR/$KGRAFT_MODULE_NAME.ko

	if [ ! -e /sys/kernel/kgraft/$KGRAFT_SYSFS_NAME ]; then
		echo "kGraft sys directory not touched, aborting"
		exit 1
	fi
}

function wait_for_patch() {
	KGRAFT_IN_PROGRESS_COUNTER=0
	while [ "$(cat /sys/kernel/kgraft/in_progress)" -ne 0 ]; do
		for PROC in /proc/[0-9]*; do
			if [ -r $PROC/kgr_in_progress ] && [ "$(cat $PROC/kgr_in_progress)" -ne 0 ]; then
				PID=$(echo $PROC | cut -d/ -f3)
				kill -STOP $PID | kill -CONT $PID
			fi
		done
		sleep 1

		KGRAFT_IN_PROGRESS_COUNTER=$((KGRAFT_IN_PROGRESS_COUNTER+1))
		if [ -n "$KGRAFT_MAX_WAIT" ] && [ $KGRAFT_MAX_WAIT -le $KGRAFT_IN_PROGRESS_COUNTER ]; then
			echo "Pending processes"
			for PROC in /proc/[0-9]*; do
				if [ -r $PROC/kgr_in_progress ] && [ "$(cat $PROC/kgr_in_progress)" -ne 0 ]; then
					echo $PROC
				fi
			done | sed 's#/proc/##g;' | xargs ps up

			die "Timed out while waiting for kGraft to finish patching."
		fi
	done
}

for PATCH in $TUNING_KGRAFT_PATCHES; do
	insert_patch
	wait_for_patch
done

for PATCH in $TUNING_KGRAFT_PATCHES_NOWAIT; do
	insert_patch
done

