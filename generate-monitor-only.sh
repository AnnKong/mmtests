#!/bin/bash
DIRNAME=`dirname $0`
export SCRIPTDIR=`cd "$DIRNAME" && pwd`
CONFIG=$SCRIPTDIR/config

usage() {
	echo "$0 [-mn] [-c path_to_config] runname"
	echo
	echo "-c|--config      Use MMTests config, default is top-level config"
	echo "-h|--help        Prints this help."
}

# Parse command-line arguments
ARGS=`getopt -o kmnc:h --long help,config: -n generate-monitor-only.sh -- "$@"`
eval set -- "$ARGS"
while true; do
	case "$1" in
		-c|--config)
			CONFIG=$2
			shift 2
			;;
		-h|--help)
			usage
			KVM_ARGS="$KVM_ARGS $1"
			exit $SHELLPACK_SUCCESS
			;;
		--)
			break
			;;
		*)
			echo ERROR: Unrecognised option $1
			usage
			exit $SHELLPACK_ERROR
			;;
	esac
done

# Take the unparsed option as the parameter
shift
export RUNNAME=$1
export MMTEST_ITERATION=$2

if [ -z "$RUNNAME" ]; then
	echo "ERROR: Runname parameter must be specified"
	usage
	exit -1
fi

. $SCRIPTDIR/shellpacks/common.sh
. $SCRIPTDIR/shellpacks/common-config.sh
. $SCRIPTDIR/shellpacks/deferred-monitors.sh

# Generate reference tree
echo Creating reference tree
mkdir -p $SHELLPACK_TEMP || die Failed to create temporary directory
cd $SHELLPACK_TOPLEVEL
if [ ! -e rn-mmtests.sh -a ! -e .git ]; then
	die Failed to identify top-level mmtests git tree
	exit -1
fi
git archive --format=tar --prefix=mmtests-monitor-$RUNNAME/ `git rev-parse HEAD` | gzip -c - > $SHELLPACK_TEMP/mmtests-monitor-${RUNNAME}.tar.gz || die Failed to create $SHELLPACK_TEMP/mmtests-monitor-${RUNNAME}.tar.gz
cd $SHELLPACK_TEMP || die Failed to switch to temporary directory
tar -xf mmtests-monitor-${RUNNAME}.tar.gz || die Failed to expand reference tree
cd $SHELLPACK_TEMP/mmtests-monitor-${RUNNAME} || die Failed to switch to reference tree
TREE_MMTESTS=$SHELLPACK_TEMP/mmtests-monitor-${RUNNAME}

echo Copying configuration
echo 'DIRNAME=`dirname $0`' > $TREE_MMTESTS/config || die Failed to write $TREE_MMTESTS/config
echo 'SCRIPTDIR=`cd "$DIRNAME" && pwd`' >> $TREE_MMTESTS/config
echo 'export PATH=$SCRIPTDIR/bin:$PATH' >> $TREE_MMTESTS/config
echo 'export SWAP_CONFIGURATION=default' >> $TREE_MMTESTS/config
echo 'export MMTESTS=monitor' >> $TREE_MMTESTS/config
grep "export RUN_" $CONFIG >> $TREE_MMTESTS/config || die Failed to copy profile parameters
grep "export OPROFILE_REPORT" $CONFIG >> $TREE_MMTESTS/config
echo 'export RUN_MONITOR=yes' >> $TREE_MMTESTS/config
grep "export MONITOR" $CONFIG >> $TREE_MMTESTS/config
sed -i -e '/^#/d' $TREE_MMTESTS/config

echo Altering auto-install commands
sed -i -e 's/install -y/install/' $TREE_MMTESTS/bin/install-depends
sed -i -e '/install-depends/d' $TREE_MMTESTS/run-mmtests.sh

echo Altering top-level execution script
sed -i -e '/reset_transhuge/d' $TREE_MMTESTS/run-mmtests.sh
sed -i -e '/Using default TESTDISK_DIR/d' $TREE_MMTESTS/run-mmtests.sh

echo Removing some scripts
rm $TREE_MMTESTS/bin/stap-fix.sh
rm $TREE_MMTESTS/compare-huge.sh
rm $TREE_MMTESTS/dashboard-*
rm $TREE_MMTESTS/generate-monitor-only.sh
rm $TREE_MMTESTS/kvm.conf
rm $TREE_MMTESTS/prebuild-*
rm $TREE_MMTESTS/profile-disabled-hooks*
rm $TREE_MMTESTS/README
rm $TREE_MMTESTS/run-kvm.sh
rm -rf $TREE_MMTESTS/configs
rm -rf $TREE_MMTESTS/micro
rm -rf $TREE_MMTESTS/shellpack_src
rm -rf $TREE_MMTESTS/stap-patches
rm -rf $TREE_MMTESTS/stap-scripts
rm -rf $TREE_MMTESTS/subreport
rm -rf $TREE_MMTESTS/vmr
mkdir $TREE_MMTESTS/shellpacks/tmp
mv $TREE_MMTESTS/shellpacks/shellpack-bench-monitor $TREE_MMTESTS/shellpacks/tmp
mv $TREE_MMTESTS/shellpacks/shellpack-install-monitor $TREE_MMTESTS/shellpacks/tmp
rm $TREE_MMTESTS/shellpacks/shellpack-bench-*
rm $TREE_MMTESTS/shellpacks/shellpack-install-*
mv $TREE_MMTESTS/shellpacks/tmp/* $TREE_MMTESTS/shellpacks
rmdir $TREE_MMTESTS/shellpacks/tmp
mkdir $TREE_MMTESTS/drivers/tmp
mv $TREE_MMTESTS/drivers/driver-monitor.sh $TREE_MMTESTS/drivers/tmp
rm $TREE_MMTESTS/drivers/driver-*.sh
mv $TREE_MMTESTS/drivers/tmp/driver-monitor.sh $TREE_MMTESTS/drivers
rmdir $TREE_MMTESTS/drivers/tmp

echo Creating tarball of mmtests in monitor-only mode
cd $SHELLPACK_TEMP
tar -czf mmtests-monitor-${RUNNAME}.tar.gz mmtests-monitor-${RUNNAME} || die Failed to create tarball

echo Creating self-executing script
cat > $SCRIPTDIR/gather-monitor-${RUNNAME}.sh << EOF
#!/bin/bash
echo Extracting
HEADER=\`awk '/^=== BEGIN MONITOR SCRIPTS ===/ { print NR + 1; exit 0; }' \$0\`
tail -n +\$HEADER \$0 | base64 -d > mmtests-monitor-${RUNNAME}.tar.gz
if [ \$? -ne 0 ]; then
	echo ERROR: Failed to self-extract, aborting.
	exit -1
fi
tar -xzf mmtests-monitor-${RUNNAME}.tar.gz
if [ \$? -ne 0 ]; then
	echo ERROR: Failed to extract embedded tar archive
	exit -1
fi
rm mmtests-monitor-${RUNNAME}.tar.gz

echo Executing monitor script, follow instructions on screen
cd mmtests-monitor-$RUNNAME
if [ \$? -ne 0 ]; then
	echo ERROR: Failed to access monitor scripts
	exit -1
fi
./run-mmtests.sh $RUNNAME
PACKAGENAME="logs-$RUNNAME-\`date +%Y%m%d-%H%M-%S\`.tar.gz"
tar -czf ../\$PACKAGENAME work/log
if [ \$? -ne 0 ]; then
	cd ..
	rm -rf mmtests-monitor-$RUNNAME
	echo ERROR: Failed to archive logs gathered
	exit -1
fi
cd ..
rm -rf mmtests-monitor-$RUNNAME

echo Logs successfully packed in \$PACKAGENAME
exit 0
=== BEGIN MONITOR SCRIPTS ===
EOF
base64 mmtests-monitor-${RUNNAME}.tar.gz >> $SCRIPTDIR/gather-monitor-${RUNNAME}.sh || \
	die Failed to base64 encode tar file
rm -rf $SHELLPACK_TEMP
chmod u+x $SCRIPTDIR/gather-monitor-${RUNNAME}.sh

echo Success
echo Self-extracting script located at $SCRIPTDIR/gather-monitor-${RUNNAME}.sh

exit $SHELLPACK_SUCCESS
