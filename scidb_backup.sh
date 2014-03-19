#!/bin/bash
#
# A basic script that backs up SciDB databases to files and reloads them.
# Run this script from the coordinator instance. The script uses iquery
# and assumes it is available in the PATH.
#
# TODO: Back up and restore array versions. One idea might be this:
# For each array:
#   store the first version
#   for each version > 1:
#     save the array to a pipe and diff the pipe against the fist
#     version, saving that to a file.
# And then reverse this process for restore. Anyway, somebody needs to
# write this!

unalias iquery >/dev/null 2>&1
read -d '' usage << "eof"

Save SciDB data with:
./scidb_backup.sh --save-opaque <directory to save data to> [--parallel]
 [--pattern PTRN] [--allVersions] [-z]
  -or-
./scidb_backup.sh --save-binary <directory to save data to> [--parallel]
 [--pattern PTRN] [--allVersions] [-z]
  -or-
./scidb_backup.sh --save-text <directory to save data to> [--parallel]
 [--pattern PTRN] [--allVersions] [-z]

Restore SciDB data with:
./scidb_backup.sh --restore-opaque <directory containing saved data> [--parallel]
 [--pattern PTRN] [--allVersions] [-z]
  -or-
./scidb_backup.sh --restore-binary <directory containing saved data> [--parallel] 
 [--pattern PTRN] [--allVersions] [-z]
  -or-
./scidb_backup.sh --restore-text <directory containing saved data> [--parallel] 
 [--pattern PTRN] [--allVersions] [-z]

Run this script from the SciDB coordinator node.

Specify the optional parallel flag to indicate parallel save/load. When
parallel save or load is specified, the directory path name serves as a base
name for a set of numbered data directories, one for each SciDB instance. Data
will be saved in parallel by each instance into its directory. If the numbered
data directories don't exist, they will be created on each node. This option
requires ssh to set up the directories on each node.

If the parallel flag is not specified, then the backup data are saved to the
specified directory path only on the coordinator instance.  If the backup
directory does not already exist, then it will be created.

Specifying pattern switch causes the program to save/restore only those
arrays matching the pattern.  The value for the pattern switch should be a
grep-like string.  For instance, if scidb has arrays A1,A2,B1,C1, and the 
specified pattern value is "A.*", the script will save only A1 and A2.
Also, if all arrays have been previously backed up, specifying pattern value
"A.*" on a restore command will load only A1 and A2 into scidb.

The option --allVersions saves all versions of arrays currently in scidb.
The backup folders will contain files named <Array>@1, <Array>@2, and so 
forth where the number after @ character is one of the array versions.  If
the backup was performed with --allVersions switch, the same switch should
be specified during the restore operation.

Option -z directs the utility to compress/decompress saved array data with
gzip.

The script assumes that SciDB is running on its default port.

The opaque methods are faster and more general, but sometimes the opaque save
format does not work between SciDB versions. In such cases, use the binary
methods.
eof

NODES="0"
ARG_ALL_VERSIONS="false"
declare -A delete_links

declare -A NODE_NAMES

[ $# -lt 2 ] && echo "${usage}" && exit 1
##############################################################################
# Process command line options:

ORIG_ARGS=$*

while [ $# -gt 0 ] ;
do 
  case "$1" in
    --save-binary) ARG_ACTION="save-binary" ;;
    --save-text) ARG_ACTION="save-text"; SAVE_FORMAT="'text'" ;;
    --save-opaque) ARG_ACTION="save-opaque"; SAVE_FORMAT="'opaque'" ;;
    --restore-binary) ARG_ACTION="restore-binary" ;;
    --restore-text) ARG_ACTION="restore-text"; SAVE_FORMAT="'text'" ;;
    --restore-opaque) ARG_ACTION="restore-opaque"; SAVE_FORMAT="'opaque'";;
    --parallel) NODES="-1" ;;
    --allVersions) ARG_ALL_VERSIONS="true" ;;
    -z) ARG_SAVE_GZIP="1" ;;
    --pattern) set -f; shift; ARG_PATTERN="$1"; set +f ;;
    *) ARG_PATH="$1" ;;
  esac
  shift
done


if [ -z ${ARG_PATTERN} ] ;
then
  set -f 
  ARG_PATTERN=".*" 
  set +f
fi

##############################################################################
[ -z ${ARG_ACTION} ] && echo "${usage}" && exit 1
[ -z ${ARG_PATH} ] && echo "${usage}" && exit 1

#.............................................................................
# Check the specified options and do some initial setup for saving/restoring:
if test ${NODES} -eq "-1" ; then
  echo "Parallel save/load"
# Parallel save/load
  #NODES="-1"
  apath="$(mkdir -p ${ARG_PATH} && readlink -f ${ARG_PATH})/"
  path="$(basename ${apath})/"
# In this case, the manifest is only stored on the coordinator.
  mpath="$(echo ${apath} | sed s:\/$:\.1\/:)"
  mkdir -p "${mpath}"
else
  path="$(mkdir -p ${ARG_PATH} && readlink -f ${ARG_PATH})/"
  if test ! -d "${path}"; then
    echo "${usage}"
    exit 2
  fi
  mpath="${path}"
fi

if [ ${ARG_ALL_VERSIONS} == "false" ] ;
then
    LIST_QUERY="list('arrays')"
    QUERY_TYPE="-aq"
    VERSION_NAME_FILTER="s/\@/\@/" # Command does nothing.
else
    LIST_QUERY="SELECT * FROM sort(list('arrays',true),id)"
    QUERY_TYPE="-q"
    VERSION_NAME_FILTER="/\@/!d" # Command keeps only versioned names (those with @ in them).
fi

##############################################################################
# Function to create directories for parallel save/load.
create_dirs ()
{
  links_only="0"
  if [ -z ${2} ];
  then
    links_only="0"
  else
    links_only="1"
  fi
  abspath="$(readlink -f ${1})"
  relpath="$(basename ${abspath})"
  declare -A nodes
# We manually loop here instead of using read because read uses a subprocess
# and we want access to the 'nodes' array.
  x=$(iquery -ocsv -aq "list('instances')" | sed 1d)
  N=$(echo "${x}" | wc -l)
  j=1
  while test ${j} -le ${N};do
    line=$(echo "${x}" | sed -n ${j}p)
    instance="$(echo ${line} | sed -e "s/,.*//" | tr -d "'")"
    ipath="$(echo $line | sed -e "s/.*,//" | tr -d "'")/${relpath}"
    if test ${links_only} == "0" ;
    then
      nodes[${instance}]="${nodes[${instance}]};mkdir -p ${abspath}.${j}; ln -snf ${abspath}.${j} ${ipath}"
    else
      nodes[${instance}]="${nodes[${instance}]}; ln -snf ${abspath}.${j} ${ipath}"
      delete_links[${instance}]="${delete_links[${instance}]}; rm -f ${ipath} 2>/dev/null"
    fi
    j=$(($j + 1))
  done
# Run one command per node to create all the directories on that node
  for node in "${!nodes[@]}"; do
    cmd=$(echo ${nodes[${node}]} | sed -e "s/^;//g")
    ssh -n ${node} "${cmd}" &
    echo ssh ${node} "${cmd}"
  done
  NODE_NAMES=${!nodes[@]}
  wait
}
parallelSaveQueryWithGzip()
{
    local srcArray=${1}
    local filePath=${2}
    local dstOpt=${3}
    local format=${4}

    local bName=$(basename ${filePath})
    local dirPath=$(echo ${ARG_PATH} | sed s:\/*$::)
    # Create pipes:
    local instance_info=$(iquery -ocsv -aq "list('instances')" | sed 1d)
    local N=$(echo "${instance_info}" | wc -l)
    
    
    local j=1
    declare -A pipeCommands
    declare -A gzipCommands
    
    hosts="$(iquery -ocsv -aq "list('instances')" | sed 1d | sed s/,.*$// | sed s/\'//g | tr '\n' ' ')"
    # Roll the pipe creation commands here:
    for host in ${hosts}; do 
	pipeCommands[${host}]="${pipeCommands[${host}]}; rm -f ${dirPath}.${j}/${bName}; mkfifo --mode=666 ${dirPath}.${j}/${bName}"
        j=$(($j + 1))
    done
    # Roll the gzip commands here:
    j=1
    for host in ${hosts}; do
	gzipCommands[${host}]="${gzipCommands[${host}]}; gzip -c < ${dirPath}.${j}/${bName} > ${dirPath}.${j}/${bName}.gz && mv ${dirPath}.${j}/${bName}.gz ${dirPath}.${j}/${bName}"
	j=$(($j + 1))
    done

    # Execute the pipe-making commands via ssh here:
    for host in "${!pipeCommands[@]}"; do
	cmd=$(echo ${pipeCommands[${host}]} | sed -e "s/^;//g")
	#echo "host = ${host}; cmd = ${cmd}"
	ssh -n ${host} "${cmd}" &
    done
    wait

    # Run the parallel save query:
    (runSaveQuery ${srcArray} "'${filePath}'" ${dstOpt} "${format}") &
    
    # Execute the gzip commands via ssh here:
    for host in "${!gzipCommands[@]}"; do
	cmd=$(echo ${gzipCommands[${host}]} | sed -e "s/^;//g")
	#echo "host = ${host}; cmd = ${cmd}"
	ssh -n ${host} "${cmd}" &
    done
    wait
}
parallelRestoreQueryWithGzip()
{
    local unpackSchema=${1}
    local finalSchema=${2}
    local filePath=${3}
    local dstOpt=${4}
    local format=${5}
    local arrayName=${6}

    local bName=$(basename ${filePath})
    local dirPath=$(echo ${ARG_PATH} | sed s:\/*$::)
    # Create pipes:
    local instance_info=$(iquery -ocsv -aq "list('instances')" | sed 1d)
    local N=$(echo "${instance_info}" | wc -l)
    
    local j=1

    unset pipeCommands

    declare -A pipeCommands
    declare -A gunzipCommands
    declare -A cleanupCommands

    hosts="$(iquery -ocsv -aq "list('instances')" | sed 1d | sed s/,.*$// | sed s/\'//g | tr '\n' ' ')"
    # Roll the pipe creation commands here:
    for host in ${hosts}; do 
	pipeCommands[${host}]="${pipeCommands[${host}]}; rm -f ${dirPath}.${j}/${bName}.p; mkfifo --mode=666 ${dirPath}.${j}/${bName}.p"
        j=$(($j + 1))
    done
    # Roll the gunzip commands here:
    j=1
    for host in ${hosts}; do 
	gunzipCommands[${host}]="${gunzipCommands[${host}]}; (cat ${dirPath}.${j}/${bName} | gzip -d -c > ${dirPath}.${j}/${bName}.p)"
        j=$(($j + 1))
    done
    # Roll the cleanup commands here:
    j=1
    for host in ${hosts}; do 
	cleanupCommands[${host}]="${cleanupCommands[${host}]}; rm -f ${dirPath}.${j}/${bName}.p"
        j=$(($j + 1))
    done

    # Execute the pipe-making commands via ssh here:
    for host in "${!pipeCommands[@]}"; do
	cmd=$(echo ${pipeCommands[${host}]} | sed -e "s/^;//g")
	#echo "host = ${host}; cmd = ${cmd}"
	ssh -n ${host} "${cmd}" &
    done
    wait
    # Execute the gunzip commands via ssh here:
    for host in "${!gunzipCommands[@]}"; do
	cmd=$(echo ${gunzipCommands[${host}]} | sed -e "s/^;//g")
	#echo "host = ${host}; cmd = ${cmd}"
	ssh -n ${host} "${cmd}" &
    done

    runRestoreQuery "${unpackSchema}" "${finalSchema}" "'${filePath}.p'" ${dstOpt} ${format} ${arrayName} && true

    # Execute the cleanup commands via ssh here:
    for host in "${!cleanupCommands[@]}"; do
	cmd=$(echo ${cleanupCommands[${host}]} | sed -e "s/^;//g")
	#echo "host = ${host}; cmd = ${cmd}"
	ssh -n ${host} "${cmd}" &
    done
    wait
}
runSaveQuery ()
{
    local srcArray=${1}
    local filePath=${2}
    local dstOpt=${3}
    local format=${4}
    
    local query="save(${srcArray},${filePath}, ${dstOpt}, ${format})"

    iquery -ocsv -naq "${query}"
}
runRestoreQuery ()
{
    local unpackSchema=${1}
    local finalSchema=${2}
    local filePath=${3}
    local dstOpt=${4}
    local format=${5}
    local arrayName=${6}
    local query=""
    if [ ${ARG_ACTION} == "restore-text" ] || [ ${ARG_ACTION} == "restore-opaque" ] ;
    then
	query="store(input(${unpackSchema}, ${filePath}, ${dstOpt}, ${format}),${arrayName})" > /dev/null 
    else
	query="store(redimension(input(${unpackSchema},${filePath},${dstOpt},${format}),${finalSchema}),${arrayName})" > /dev/null
    fi
    iquery -naq "${query}"
}

saveArray ()
{
    local srcArray=${1}
    local filePath=${2}
    local dstOpt=${3}
    local format=${4}

    if [ -z ${ARG_SAVE_GZIP} ] ;
    then
    rm -f ${filePath} > /dev/null 2>&1
	runSaveQuery ${srcArray} "'${filePath}'" ${dstOpt} "${format}"
	return
    fi

    if [ "${NODES}" == "-1" ] ; then
	parallelSaveQueryWithGzip ${srcArray} ${filePath} ${dstOpt} "${format}" "${NODE_NAMES}"
	return
    fi

    # We need to save the zipped array in non-parallel mode.
    rm -f ${filePath} > /dev/null 2>&1
    mkfifo --mode=666 ${filePath}
    (runSaveQuery ${srcArray} "'${filePath}'" ${dstOpt} "${format}") & gzip -c < ${filePath} > ${filePath}.gz && mv ${filePath}.gz ${filePath} 

}
restoreArray ()
{
    local unpackSchema=${1}
    local finalSchema=${2}
    local filePath=${3}
    local dstOpt=${4}
    local format=${5}
    local arrayName=${6}
    local versionedName=${7}

    if [ -z ${ARG_SAVE_GZIP} ] ;
    then
	runRestoreQuery "${unpackSchema}" "${finalSchema}" "'${filePath}'" ${dstOpt} "${format}" ${arrayName}
	return
    fi
    if [ "${NODES}" == "-1" ] ; then
	parallelRestoreQueryWithGzip "${unpackSchema}" "${finalSchema}" "${filePath}" ${dstOpt} "${format}" ${arrayName}
	return
    fi

    # We need to restore from gzip.
    rm ${filePath}.p > /dev/null 2>&1
    mkfifo --mode=666 ${filePath}.p
    (cat ${filePath} | gzip -d -c > ${filePath}.p) & runRestoreQuery "${unpackSchema}" "${finalSchema}" "'${filePath}.p'" ${dstOpt} "${format}" ${arrayName} && true
    rm ${filePath}.p
}
removeArray()
{
    local arrayName=${1}
    
    local testVersion=$(echo ${arrayName} | grep \@)
    
    # Check if the array name is "version-ed":
    if [ -n "${testVersion}" ] ;
    then
	local version=$(echo ${arrayName} | sed s/^[^\@]*\@//)
	local no_ver_name=$(echo ${arrayName} | sed s/\@[0-9]*//)
    # If array name has a version, then check if it is 1
    # because we want to remove prior array only once from the 
    # database (all other versions will be restored on top).
	if [ ${version} == "1" ] ;
	then
	    arrayName=${no_ver_name}
	else
	    return
	fi
    fi
    iquery -naq  "remove(${arrayName})" > /dev/null 2>&1
}
removeDataLinks()
{
    # Remove links from data directories:
    for node in "${!delete_links[@]}"; do
        cmd=$(echo ${delete_links[${node}]} | sed -e "s/^;//g")
        ssh -n ${node} "${cmd}" &
        echo ssh ${node} "${cmd}"
    done
    wait
}
checkRestoreOptions()
{
    local gzip_test=""
    local action_option=""
    # Check parallel option.
    if [ "${NODES}" == "-1" ] ;
    then
        if test ! -f "${mpath}.manifest"; then
          echo "Error: parallel restore attempted, but ${mpath}.manifest file does not exist!"
          exit 4
        fi
        local p_test="$(cat ${mpath}.save_opts | grep '\-\-parallel')"
        if [ -z "${p_test}" ] ;
        then
            echo "ERROR: backup was produced without --parallel option!  Please re-run the restore command without --parallel option!"
            exit 1
        fi
    else
        if test ! -f "${mpath}.manifest"; then
          echo "Error: non-parallel restore attempted, but ${mpath}.manifest file does not exist!"
          exit 4
        fi
        local p_test="$(cat ${mpath}.save_opts | grep '\-\-parallel')"
        if [ -n "${p_test}" ] ;
        then
            echo "ERROR: backup was produced with --parallel option!  Please re-run the restore command with --parallel option!"
            exit 1
        fi
    fi
    if [ -z ${ARG_SAVE_GZIP} ] ;
    then
        local zopt_test="$(cat ${mpath}.save_opts | grep '\-z')"
        if [ -n "${zopt_test}" ] ;
        then
            echo "ERROR: backup was produced with -z option!  Please re-run the restore command and specify -z option!"
            exit 1
        fi
    else
        zopt_test="$(cat ${mpath}.save_opts | grep '\-z')"
        if [ -z "${zopt_test}" ] ;
        then
            echo "ERROR: backup was produced without -z option!  Please re-run the restore command without -z option!"
            exit 1
        fi
    fi
    local action_option="$(echo ${ARG_ACTION} | sed s/restore/save/)"
    local action_test="$(cat ${mpath}.save_opts | grep ${action_option})"
    if [ -z "${action_test}" ] ;
    then
        echo "ERROR: backup was produced with different options:"
        cat ${mpath}.save_opts
        echo "Please adjust options accordingly and re-run the restore operations."
        exit 1  
    fi
}
##############################################################################
# Backup array data (opaque)
if [ ${ARG_ACTION} == "save-opaque" ] || [ ${ARG_ACTION} == "save-text" ] ; then
  [ "${NODES}" == "-1" ] && create_dirs ${apath}
  # Save array names in the manifest file.
  iquery -ocsv ${QUERY_TYPE}  "${LIST_QUERY}" | sed 1d | sed -n "/${ARG_PATTERN}/p" | sed ${VERSION_NAME_FILTER} > "${mpath}.manifest"
  # Save the options in the .save_opts
  echo ${ORIG_ARGS} > "${mpath}.save_opts"
  a=$(cat ${mpath}.manifest | cut -d , -f 1 | sed -e "s/'//g")
  arraysSaved=0
  for x in ${a};do
    echo "Archiving array ${x}"
    saveArray "${x}" "${path}${x}" "${NODES}" "${SAVE_FORMAT}"
    arraysSaved=$(($arraysSaved + 1))
  done
  echo "Saved ${arraysSaved} arrays."
  exit 0
  # Remove data links from scidb instance data directories:
  removeDataLinks
fi
##############################################################################
# Backup array data (binary)
if test "${ARG_ACTION}" == "save-binary";
then
  [ "${NODES}" == "-1" ] && create_dirs ${apath}
  # Save array names in the manifest file.
  iquery -ocsv ${QUERY_TYPE}  "${LIST_QUERY}" | sed 1d | sed -n "/${ARG_PATTERN}/p" | sed ${VERSION_NAME_FILTER} > "${mpath}.manifest"
  # Save the options in the .save_opts
  echo ${ORIG_ARGS} > "${mpath}.save_opts"
  arraysSaved=0
  while read x;
  do
    name=$(echo "${x}" | cut -d , -f 1 | sed -e "s/'//g")
# Flatten the array as a 1-d array. Warning, we assume that the array does
# not have a dimension nor an attribute named "__row."
    unschema=$(iquery -ocsv -aq "show('unpack(${name},__row)','afl')" | sed 1d)
    a=$(echo "${unschema}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/\s*DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    #query="save(unpack(${name},__row), '${path}${name}', ${NODES}, '${fmt}')"
    echo "Archiving array ${name}"
    #iquery -naq "${query}"
    saveArray "unpack(${name},__row)" "${path}${name}" ${NODES} "'${fmt}'"
    arraysSaved=$(($arraysSaved + 1))
  done < "${mpath}.manifest"
  echo "Saved ${arraysSaved} arrays."
  removeDataLinks
  exit 0
fi
##############################################################################
# Validate restore options.
checkRestoreOptions

# Restore binary data:
if test ! -f "${mpath}.manifest"; then
  echo "Error: can't find .manifest file!"
  exit 4
fi
#.............................................................................
if test "${ARG_ACTION}" == "restore-binary"; then
  
  [ "${NODES}" == "-1" ] && create_dirs ${apath} 1
  arraysSaved=0
  while read x;
  do
    fname=$(echo "${x}" | cut -d , -f 1 | grep "${ARG_PATTERN}" | sed -e "s/'//g")
    name=$(echo "${fname}" | sed s/\@[^\@]*//g)
    if [ -z ${name} ] ;
    then
      continue
    fi
# The final array schema:
    s=$(echo ${x} | sed -e "s/.*</</" | sed -e "s/'.*//g")
# The unpack array schema:
    u=$(iquery -ocsv -aq "show('unpack(input(${s},\'/dev/null\'),__row)','afl')" | sed 1d | sed -e "s/.*</</" | tr -d "'")
    a=$(echo "${u}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/\s*DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    #query="store(redimension(input(${u},'${path}${fname}',${NODES},'${fmt}'),${s}),${name})"
    echo "Restoring array ${fname}"
    removeArray ${fname}
    restoreArray "${u}" "${s}" "${path}${fname}" ${NODES} "'${fmt}'" ${name}
    arraysSaved=$(($arraysSaved + 1))
  done < ${mpath}.manifest

  echo "Restored ${arraysSaved} arrays."
#.............................................................................
# Remove links from data directories:
  removeDataLinks
#  for node in "${!delete_links[@]}"; do
#    cmd=$(echo ${delete_links[${node}]} | sed -e "s/^;//g")
#    ssh -n ${node} "${cmd}" &
#    echo ssh ${node} "${cmd}"
#  done
#  wait
  exit 0
fi
##############################################################################
# Restore opaque data (currently disabled):
if [ ${ARG_ACTION} != "restore-opaque" ] && [ ${ARG_ACTION} != "restore-text" ] ; 
then
  echo "${usage}"
  exit 3
fi

# Validate restore options.
checkRestoreOptions

[ "${NODES}" == "-1" ] && create_dirs ${apath} 1
# Restore array data.
while read line; do
  x=$(echo ${line} | cut -d , -f 1 | grep "${ARG_PATTERN}" | sed -e "s/'//g")
  name=$(echo ${x} | sed s/\@[^\@]*$//)
  if [ -z ${x} ] ;
  then
    continue
  fi
  s=$(echo ${line} | sed -e "s/.*</</" | sed -e "s/'.*//g")
  # Pass in the version-ed name of the array (in case of all-version
  # operation).  We only delete the array when processing version 1.
  removeArray ${x}
  echo "Restoring array ${x}"
  restoreArray "${s}" ""  "${path}${x}" ${NODES} "${SAVE_FORMAT}" ${name}
done < ${mpath}.manifest
#.............................................................................
# Remove links from data directories:
removeDataLinks
#for node in "${!delete_links[@]}"; do
#  cmd=$(echo ${delete_links[${node}]} | sed -e "s/^;//g")
#  ssh -n ${node} "${cmd}" &
#  echo ssh ${node} "${cmd}"
#done
wait

