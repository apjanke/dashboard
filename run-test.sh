#!/usr/bin/env bash
#
# This script creates a temporary matlab script for a specific test and
# a specific FieldTrip revision, starts MATLAB and executes the temporary
# script.
#
# Use as either one of these
#   run-test.sh <TESTSCRIPT> <FIELDTRIPDIR> <LOGDIR> <MATLABCMD>
#   run-test.sh <TESTSCRIPT> <FIELDTRIPDIR> <LOGDIR>
#   run-test.sh <TESTSCRIPT> <FIELDTRIPDIR>
#   run-test.sh <TESTSCRIPT>
#
# This script is scheduled for execution on the torque cluster by schedule-test.sh

# optenv does not load modules when executed as PBS job
source /opt/optenv.sh

module load openmeeg
module load cluster
module load fsl

set -u -e  # exit on error or if variable is unset

TESTSCRIPT=`readlink -f $1`

if [ "$#" -ge 2 ]; then
FIELDTRIPDIR=$2
else
FIELDTRIPDIR=$HOME/matlab/fieldtrip
fi

DASHBOARDDIR=$(dirname $(readlink -f $0))
REVISION=$(cd ~/matlab/fieldtrip && git rev-parse --short HEAD)

if [ "$#" -ge 3 ]; then
LOGDIR=$3
mkdir -p $LOGDIR
else
# LOGDIR=$HOME/`date +'%FT%H:%M:%S'`
LOGDIR=$DASHBOARDDIR/logs/$REVISION
mkdir -p $LOGDIR
rm $DASHBOARDDIR/logs/latest
ln -s $LOGDIR $DASHBOARDDIR/logs/latest
fi

if [ "$#" -ge 4 ]; then
MATLABCMD=$4
else
MATLABCMD="/opt/matlab/R2017b/bin/matlab -nodesktop -nosplash -nodisplay -singleCompThread"
fi

if [[ $MATLABCMD == *"matlab"* ]]; then
XUNIT=`readlink -f /home/common/matlab/xunit`
elif [[ $MATLABCMD == *"octave"* ]]; then
XUNIT=`readlink -f $HOME/matlab/xunit-octave`
else
>&2 echo Error: unknown MATLABCMD $MATLABCMD
fi

# the FieldTrip test script test to be executed is passed with the full path
TESTDIR=`dirname $TESTSCRIPT`
TEST=`basename $TESTSCRIPT .m`

# Create temp file for job submission with so-called "here document":
MATLABSCRIPT=`mktemp $LOGDIR/test_XXXXXXXX.m`
cat > $MATLABSCRIPT <<EOF
%-------------------------------------------------------------------------------
% this MATLAB script will be automatically removed when execution has finished

try

  restoredefaultpath
  addpath $FIELDTRIPDIR 
  addpath $FIELDTRIPDIR/test  % for dccnpath

  global ft_default
  ft_default = [];
  ft_default.feedback = 'no';
  ft_default.checkconfig = 'loose';
  ft_default.trackusage = 'no';
  % ft_default.trackconfig = 'no';

  ft_defaults

  cd $TESTDIR
  ft_test run $TEST

catch err
  disp(err)
end

exit
%-------------------------------------------------------------------------------
EOF

MDIR=`dirname ${MATLABSCRIPT}`
MFUN=${MATLABSCRIPT##*/}  # remove dir
MFUN=${MFUN%.*}           # remove extension
# $HOME/bin/shmwait 15    # start different instances 10 seconds apart

if [[ $MATLABCMD == *"matlab"* ]]; then
$MATLABCMD -r "cd $MDIR ; $MFUN"
elif [[ $MATLABCMD == *"octave"* ]]; then
$MATLABCMD ${MATLABSCRIPT}
else
>&2 echo Error: unknown MATLABCMD $MATLABCMD
fi

# remove the temp file, not the actual FieldTrip test script
rm $MATLABSCRIPT

