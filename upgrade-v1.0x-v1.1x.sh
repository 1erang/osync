#!/bin/bash

PROGRAM="Osync instance upagrade script" # Rsync based two way sync engine with fault tolerance
AUTHOR="(L) 2015 by Orsiris \"Ozy\" de Jong"
CONTACT="http://www.netpower.fr/osync - ozy@netpower.fr"
PROGRAM_VERSION="1.0x to v1.1"
PROGRAM_BUILD=2015092601

function Init {
	OSYNC_DIR=".osync_workdir"
	STATE_DIR="state"

	TREE_CURRENT_FILENAME="-tree-current-$SYNC_ID"
	TREE_AFTER_FILENAME="-tree-after-$SYNC_ID"
	TREE_AFTER_FILENAME_NO_SUFFIX="-tree-after-$SYNC_ID"
	DELETED_LIST_FILENAME="-deleted-list-$SYNC_ID"
	FAILED_DELETE_LIST_FILENAME="-failed-delete-$SYNC_ID"

	if [ "${SLAVE_SYNC_DIR:0:6}" == "ssh://" ]; then
		REMOTE_SYNC="yes"

		# remove leadng 'ssh://'
		uri=${SLAVE_SYNC_DIR#ssh://*}
		if [[ "$uri" == *"@"* ]]; then
			# remove everything after '@'
			REMOTE_USER=${uri%@*}
		else
			REMOTE_USER=$LOCAL_USER
		fi

		if [ "$SSH_RSA_PRIVATE_KEY" == "" ]; then
			SSH_RSA_PRIVATE_KEY=~/.ssh/id_rsa
		fi

		# remove everything before '@'
		_hosturiandpath=${uri#*@}
		# remove everything after first '/'
		_hosturi=${_hosturiandpath%%/*}
		if [[ "$_hosturi" == *":"* ]]; then
			REMOTE_PORT=${_hosturi##*:}
		else
			REMOTE_PORT=22
		fi
		REMOTE_HOST=${_hosturi%%:*}

		# remove everything before first '/'
		SLAVE_SYNC_DIR=${_hosturiandpath#*/}
	fi

	SSH_CMD="$(type -p ssh) $SSH_COMP -i $SSH_RSA_PRIVATE_KEY $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT"
}

function Usage {
	echo "$PROGRAM $PROGRAM_VERSION $PROGRAM_BUILD"
	echo $AUTHOR
	echo $CONTACT
	echo ""
	echo "This script migrates osync v1.0x setups to v1.1 by updating state filenames and config files."
	echo ""
	echo "Usage: upgrade.sh /path/to/config_file.conf"
	echo "Usage: upgrade.sh --master=/path/to/master/replica --slave=/path/to/local/slave/replica --sync-id=existing_id"
	echo "Usage: upgrade.sh --master=/path/to/master/replica --slave=ssh://[backupuser]@remotehost.com[:portnumber]//path/to/slave/replica --sync-id=existing_id --rsakey=/path/to/rsa/key"
	echo ""
	echo "If config file is provided, the config file itself and both replicas from config file will be updated."
	echo "If no config file provided, assume you run  the update script just like any other quicksync task."
	echo "If sync-id is not specified, it will assume handling a quicksync task."
	exit 128
}

function CheckEnvironment {
	if [ "$REMOTE_SYNC" == "yes" ]; then
		if ! type -p ssh > /dev/null 2>&1
		then
			Logger "ssh not present. Cannot start sync." "CRITICAL"
			return 1
		fi
	fi

	if ! type -p rsync > /dev/null 2>&1
	then
		Logger "rsync not present. Sync cannot start." "CRITICAL"
		return 1
	fi
}

function LoadConfigFile {
	local config_file="${1}"

	if [ ! -f "$config_file" ]; then
		echo "Cannot load configuration file [$config_file]. Sync cannot start."
		exit 1
	elif [[ "$1" != *".conf" ]]; then
		echo "Wrong configuration file supplied [$config_file]. Sync cannot start."
		exit 1
	else
		egrep '^#|^[^ ]*=[^;&]*'  "$config_file" > "./osync.$FUNCNAME.$$"
		# Shellcheck source=./sync.conf
		source "./osync.$FUNCNAME.$$"
		rm -f "./osync.$FUNCNAME.$$"
	fi
}

function _RenameStateFilesLocal {
	local state_dir="${1}" # Absolute path to statedir
	local rewrite=false

	echo "Rewriting state files in [$state_dir]."

	# Make sure there is no ending slash
	state_dir="${state_dir%/}/"

	if [ -f "$state_dir""master"$TREE_CURRENT_FILENAME ]; then
		mv -f "$state_dir""master"$TREE_CURRENT_FILENAME "$state_dir""initiator"$TREE_CURRENT_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$TREE_CURRENT_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$TREE_AFTER_FILENAME ]; then
		mv -f "$state_dir""master"$TREE_AFTER_FILENAME "$state_dir""initiator"$TREE_AFTER_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$TREE_AFTER_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$DELETED_LIST_FILENAME ]; then
		mv -f "$state_dir""master"$DELETED_LIST_FILENAME "$state_dir""initiator"$DELETED_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$DELETED_LIST_FILENAME
		else
			rewrite=true
		fi
		rewrite=true
	fi
	if [ -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME ]; then
		mv -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME "$state_dir""initiator"$FAILED_DELETE_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$FAILED_DELETE_LIST_FILENAME
		else
			rewrite=true
		fi
	fi

	if [ -f "$state_dir""master"$TREE_CURRENT_FILENAME"-dry" ]; then
		mv -f "$state_dir""master"$TREE_CURRENT_FILENAME"-dry" "$state_dir""initiator"$TREE_CURRENT_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$TREE_CURRENT_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$TREE_AFTER_FILENAME"-dry" ]; then
		mv -f "$state_dir""master"$TREE_AFTER_FILENAME"-dry" "$state_dir""initiator"$TREE_AFTER_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir""master"$TREE_AFTER_FILENAME"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$DELETED_LIST_FILENAME"-dry" ]; then
		mv -f "$state_dir""master"$DELETED_LIST_FILENAME"-dry" "$state_dir""initiator"$DELETED_LIST_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$DELETED_LIST_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME"-dry" ]; then
		mv -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME"-dry" "$state_dir""initiator"$FAILED_DELETE_LIST_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$FAILED_DELETE_LIST_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi

	if [ -f "$state_dir""slave"$TREE_CURRENT_FILENAME ]; then
		mv -f "$state_dir""slave"$TREE_CURRENT_FILENAME "$state_dir""target"$TREE_CURRENT_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$TREE_CURRENT_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$TREE_AFTER_FILENAME ]; then
		mv -f "$state_dir""slave"$TREE_AFTER_FILENAME "$state_dir""target"$TREE_AFTER_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$TREE_AFTER_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$DELETED_LIST_FILENAME ]; then
		mv -f "$state_dir""slave"$DELETED_LIST_FILENAME "$state_dir""target"$DELETED_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$DELETED_LIST_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$FAILED_DELETE_LIST_FILENAME ]; then
		mv -f "$state_dir""slave"$FAILED_DELETE_LIST_FILENAME "$state_dir""target"$FAILED_DELETE_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$FAILED_DELETE_LIST_FILENAME
		else
			rewrite=true
		fi
	fi

	if [ -f "$state_dir""slave"$TREE_CURRENT_FILENAME"-dry" ]; then
		mv -f "$state_dir""slave"$TREE_CURRENT_FILENAME"-dry" "$state_dir""target"$TREE_CURRENT_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$TREE_CURRENT_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$TREE_AFTER_FILENAME"-dry" ]; then
		mv -f "$state_dir""slave"$TREE_AFTER_FILENAME"-dry" "$state_dir""target"$TREE_AFTER_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$TREE_AFTER_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$DELETED_LIST_FILENAME"-dry" ]; then
		mv -f "$state_dir""slave"$DELETED_LIST_FILENAME"-dry" "$state_dir""target"$DELETED_LIST_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$DELETED_LIST_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""slave"$FAILED_DELETE_LIST_FILENAME"-dry" ]; then
		mv -f "$state_dir""slave"$FAILED_DELETE_LIST_FILENAME"-dry" "$state_dir""target"$FAILED_DELETE_LIST_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"slave"$FAILED_DELETE_LIST_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi

	if [ $rewrite == true ]; then
		echo "State dir rewritten."
	else
		echo "Nothing rewritten in state dir."
	fi
	}

function _RenameStateFilesRemote {

	echo "Connecting remotely to rewrite state files in [$1]."

$SSH_CMD state_dir="${1}" DELETED_LIST_FILENAME="$DELETED_LIST_FILENAME" FAILED_DELETE_LIST_FILENAME="$FAILED_DELETE_LIST_FILENAME" 'bash -s' << 'ENDSSH'

	# Make sure there is no ending slash
	state_dir="${state_dir%/}/"
	rewrite=false

	if [ -f "$state_dir""master"$DELETED_LIST_FILENAME ]; then
		mv -f "$state_dir""master"$DELETED_LIST_FILENAME "$state_dir""initiator"$DELETED_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$DELETED_LIST_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME ]; then
		mv -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME "$state_dir""initiator"$FAILED_DELETE_LIST_FILENAME
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$FAILED_DELETE_LIST_FILENAME
		else
			rewrite=true
		fi
	fi
	if [ -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME"-dry" ]; then
		mv -f "$state_dir""master"$FAILED_DELETE_LIST_FILENAME"-dry" "$state_dir""initiator"$FAILED_DELETE_LIST_FILENAME"-dry"
		if [ $? != 0 ]; then
			echo "Error while rewriting "$state_dir"master"$FAILED_DELETE_LIST_FILENAME"-dry"
		else
			rewrite=true
		fi
	fi

	if [ $rewrite == true ]; then
		echo "State dir rewritten."
	else
		echo "Nothing rewritten in state dir."
	fi
ENDSSH
	}

function RenameStateFiles {
	_RenameStateFilesLocal "$MASTER_SYNC_DIR/$OSYNC_DIR/$STATE_DIR"
	if [ "$REMOTE_SYNC" != "yes" ]; then
		_RenameStateFilesLocal "$SLAVE_SYNC_DIR/$OSYNC_DIR/$STATE_DIR"
	else
		_RenameStateFilesRemote "$SLAVE_SYNC_DIR/$OSYNC_DIR/$STATE_DIR"
	fi
}

function RewriteConfigFiles {
	local config_file="${1}"

	if ! grep "MASTER_SYNC_DIR=" "$config_file" > /dev/null; then
		echo "Config file $config_file does not seem like an osync v1.0x file."
		exit
	fi

	echo "Rewriting config file $config_file"

	#TODO: exclude occurences between doublequotes

	sed -i 's/MASTER_SYNC_DIR/INITIATOR_SYNC_DIR/g' "$config_file"
	sed -i 's/SLAVE_SYNC_DIR/TARGET_SYNC_DIR/g' "$config_file"
	sed -i 's/CONFLICT_PREVALANCE=master/CONFLICT_PREVALANCE=initiator/g' "$config_file"
	sed -i 's/CONFLICT_PREVALANCE=slave/CONFLICT_PREVALANCE=target/g' "$config_file"
}

_QUICKSYNC=0

for i in "$@"
do
	case $i in
		--master=*)
		no_maxtime=1
		MASTER_SYNC_DIR=${i##*=}
		QUICK_SYNC=$(($_QUICKSYNC + 1))
		;;
		--slave=*)
		SLAVE_SYNC_DIR=${i##*=}
		QUICK_SYNC=$(($_QUICKSYNC + 1))
		;;
		--rsakey=*)
		SSH_RSA_PRIVATE_KEY=${i##*=}
		;;
		--sync-id=*)
		SYNC_ID=${i##*=}
		;;
	esac
done

if [ $_QUICKSYNC -eq 2 ]; then
	Init
	REPLICA_DIR=${i##*=}
	RenameStateFiles

elif [ "$1" != "" ] && [ -f "$1" ] && [ -w "$1" ]; then
	CONF_FILE="$1"
	# Make sure there is no ending slash
	CONF_FILE="${CONF_FILE%/}"
	LoadConfigFile "$CONF_FILE"
	Init
	RewriteConfigFiles "$CONF_FILE"
	RenameStateFiles
else
	Usage
fi
