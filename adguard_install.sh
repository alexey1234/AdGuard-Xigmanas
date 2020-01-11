#!/bin/sh

. /etc/rc.subr
. /etc/util.subr
. /etc/configxml.subr

exerr () { echo -e "$*" >&2 ; exit 1; }
#
STAT=$(procstat -f $$ | grep -E "/"$(basename $0)"$")
FULL_PATH=$(echo $STAT | sed -r s/'^([^\/]+)\/'/'\/'/1 2>/dev/null)
START_FOLDER=$(dirname $FULL_PATH | sed 's|/adguard_install.sh||')



#Store user's inputs
# This first checks to see that the user has supplied an argument
if [ ! -z $1 ]; then
    # The first argument will be the path that the user wants to be the root folder.
    # If this directory does not exist, it is created
    AGH_ROOT=$1    
    
    # This checks if the supplied argument is a directory. If it is not
    # then we will try to create it
    if [ ! -d $AGH_ROOT ]; then
        echo "Attempting to create a new destination directory....."
        mkdir -p $AGH_ROOT || exerr "ERROR: Could not create directory!"
    fi
else
# We are here because the user did not specify an alternate location. Thus, we should use the 
# current directory as the root.
    AGH_ROOT=$START_FOLDER
fi
# create working folder	
mkdir -p $START_FOLDER/temporary || exerr "ERROR: Could not create install directory!"

echo $AGH_ROOT > /tmp/adguard.tmp
cd $START_FOLDER/temporary || exerr "ERROR: Could not access install directory!"

# Fetch the AdGuard file
echo "Retrieving the most recent version of AdGuardHome"
fetch https://static.adguard.com/adguardhome/release/AdGuardHome_freebsd_amd64.tar.gz || exerr "ERROR: Could not write to install directory!"

# Extract the files we want, stripping the leading directory, and exclude
# the git nonsense
echo "Unpacking the tarball..."
tar -xvf AdGuardHome_freebsd_amd64.tar.gz --strip-components 1
# Get rid of the tarball
rm AdGuardHome_freebsd_amd64.tar.gz
#create start stop script
cat << EOF > adguard.sh
#!/bin/sh
#
#
. /etc/rc.subr
. /etc/configxml.subr
name="AdGuardHome"
PIDFILE=/var/run/\${name}.pid

# Start/stop processes required for the ISC DHCP server
case "\$1" in

	'start')
		echo "Starting \${name}"

EOF
echo  "		"$AGH_ROOT"/\${name} 1>/var/log/\${name}.log 2>/var/log/\${name}.log &" >>adguard.sh
cat << EOF >> adguard.sh
		pid=\`/bin/ps ax | grep -w \${name} | grep -v grep | awk '{print\$1}'\`
		echo \$pid >\$PIDFILE
		echo "Done."
		;;
	'stop')
		echo "Stopping \${name}"
		pid=\`/bin/cat \$PIDFILE\`
		kill \$pid
	    rm -rf \$PIDFILE
		echo "Done."
		;;
	'status')
		if [ -s \$PIDFILE ]; then
			pid=\`/bin/ps ax | grep -w \${name} | grep -v grep | awk '{print\$1}'\`
			echo \${name} running at pid \$pid
		else
			echo  \${name} not running
		fi	
		;;
	'restart')
		echo "Restarting \${name}"
		pid=\`/bin/cat \$PIDFILE\`
		kill \$pid
EOF

echo 	"		"$AGH_ROOT"/\${name} 1>/var/log/\${name}.log 2>/var/log/\${name}.log &" >>adguard.sh
cat << EOF >> adguard.sh
		pid=\`/bin/ps ax | grep -w \${name} | grep -v grep | awk '{print\$1}'\`
		echo \$pid >\$PIDFILE
		echo "Done."
		;;
	'remove')
		echo "Remove integration"
EOF
echo "		eval" $AGH_ROOT"/uninstall.php">>adguard.sh
cat << EOF >> adguard.sh
		;;
   *)
	  echo "Usage: \$0 [ start | stop | restart | status | remove ]"
	  ;;
esac	  
EOF
echo Done
chmod 755 adguard.sh
#create crunch.php file
cat << EOF > crunch.php
#!/usr/local/bin/php-cgi -f
<?php
require_once ("guiconfig.inc");
if ( is_file( '/tmp/adguard.tmp' ) ) {
	\$rootfolder = rtrim( file_get_contents('/tmp/adguard.tmp') );
	\$sphere_record['param']['uuid'] = uuid();
	\$sphere_record['param']['enable'] = true;
	\$sphere_record['param']['protected'] = false;
	\$sphere_record['param']['name'] = 'AdGuardHome startup script';
	\$sphere_record['param']['value'] = "/usr/local/bin/php-cgi ".\$rootfolder."/adguard.sh start";
	\$sphere_record['param']['comment'] = '';
	\$sphere_record['param']['typeid'] = '2';
	if ( ! is_array(\$config['rc']['param'] ) ) \$config['rc']['param'] = array();
	\$a_param = &\$config['rc']['param'];
	if (FALSE !== (\$parid = array_search_ex("AdGuardHome startup script", \$a_param, "name"))) unset ( \$a_param[\$parid]);		
	\$config['rc']['param'] = array_merge_recursive (\$config['rc']['param'], \$sphere_record );
	write_config();
	unset (\$sphere_record);
	\$sphere_record['param']['uuid'] = uuid();
	\$sphere_record['param']['enable'] = true;
	\$sphere_record['param']['protected'] = false;
	\$sphere_record['param']['name'] = 'AdGuardHome stop script';
	\$sphere_record['param']['value'] = "/usr/local/bin/php-cgi ".\$rootfolder."/adguard.sh stop";
	\$sphere_record['param']['comment'] = '';
	\$sphere_record['param']['typeid'] = '3';
	if (FALSE !== (\$parid = array_search_ex("AdGuardHome stop script", \$a_param, "name"))) unset ( \$a_param[\$parid]);		
	\$config['rc']['param'] = array_merge_recursive (\$config['rc']['param'], \$sphere_record );
	write_config();
	echo "start and stop commands added\n";
	unlink ('/tmp/adguard.tmp');
} else {
	echo "fail when try to add start stop commands\n";
}	
?>
EOF
chmod 755 crunch.php
cat << EOF > uninstall.php
#!/usr/local/bin/php-cgi -f
<?php
require_once ("guiconfig.inc");
\$a_param = &\$config['rc']['param'];
if (FALSE !== (\$parid = array_search_ex("AdGuardHome startup script", \$a_param, "name"))) unset ( \$a_param[\$parid]);		
if (FALSE !== (\$parid1 = array_search_ex("AdGuardHome stop script", \$a_param, "name"))) unset ( \$a_param[\$parid1]);
write_config();
echo "Uninstalled\n";
	
?>
EOF
chmod 755 uninstall.php

cp -f -R $START_FOLDER/temporary/* $AGH_ROOT/

mess=`$AGH_ROOT/crunch.php`
rm $AGH_ROOT/crunch.php
echo $mess
echo "Cleanup"
cd $START_FOLDER
rm -Rf temporary/*
rmdir temporary
eval $AGH_ROOT/adguard.sh start
currentdate=`date -j +"%h %d %H:%M:%S"`
echo $currentdate "Look like success"
