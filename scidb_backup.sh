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
./scidb_backup.sh save-opaque <directory to save data to> [parallel]
  -or-
./scidb_backup.sh save-binary <directory to save data to> [parallel]

Restore SciDB data with:
./scidb_backup.sh restore-opaque <directory containing saved data> [parallel]
  -or-
./scidb_backup.sh restore-binary <directory containing saved data> [parallel]

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

The script assumes that SciDB is running on its default port.

The opaque methods are faster and more general, but sometimes the opaque save
format does not work between SciDB versions. In such cases, use the binary
methods.
eof

NODES="0"

[ $# -lt 2 ] && echo "${usage}" && exit 1

if test $# -gt 2; then
  echo "Parallel save/load"
# Parallel save/load
  NODES="-1"
  apath="$(readlink -f ${2})/"
  path="$(basename ${apath})/"
# In this case, the manifest is only stored on the coordinator.
  mpath="${apath}.1/"
  mkdir -p "${mpath}"
else
  path="$(readlink -f ${2})/"
  if test ! -d "${path}"; then
    mkdir -p "${path}"
  fi
  if test ! -d "${path}"; then
    echo "${usage}"
    exit 2
  fi
  mpath="${path}"
fi

# Create directories for parallel save/load.
create_dirs ()
{
  j=1
  abspath="$(readlink -f ${1})"
  relpath="$(basename ${abspath})"
  iquery -ocsv -aq "list('instances')" | sed 1d | while read line; do
    instance=$(echo $line | sed -e "s/,.*//" | tr -d "'")
    ipath="$(echo $line | sed -e "s/.*,//" | tr -d "'")/${relpath}"
    echo "ssh $instance \"mkdir -p ${abspath}.${j}; ln -sf ${abspath}.${j} ${ipath}\""
    ssh $instance "mkdir -p ${abspath}.${j}; ln -sf ${abspath}.${j} ${ipath}" >/dev/null 2>&1 </dev/null
    j=$(($j + 1))
  done
  wait
}


# Backup array data
if test "${1}" == "save-opaque"; then
  [ "${NODES}" == "-1" ] && create_dirs ${apath}
  iquery -ocsv -aq "list('arrays')" | sed 1d > "${mpath}.manifest"
  a=$(cat ${mpath}.manifest | cut -d , -f 1 | sed -e "s/'//g")
  for x in ${a};do
    echo "Archiving array ${x}"
    iquery -naq "save(${x}, '${path}${x}', ${NODES}, 'opaque')"
  done
  exit 0
fi

if test "${1}" == "save-binary"; then
  [ "${NODES}" == "-1" ] && create_dirs ${apath}
  iquery -ocsv -aq "list('arrays')" | sed 1d > "${mpath}.manifest"
  while read x;
  do
    name=$(echo "${x}" | cut -d , -f 1 | sed -e "s/'//g")
# Flatten the array as a 1-d array. Warning, we assume that the array does
# not have a dimension nor an attribute named "__row."
    unschema=$(iquery -ocsv -aq "show('unpack(${name},__row)','afl')" | sed 1d)
    a=$(echo "${unschema}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    query="save(unpack(${name},__row), '${path}${name}', ${NODES}, '${fmt}')"
    echo "Archiving array ${name}"
    iquery -naq "${query}"
  done < "${mpath}.manifest"
  exit 0
fi

if test ! -f "${mpath}.manifest"; then
  echo "Error: can't find .manifest file!"
  exit 4
fi

if test "${1}" == "restore-binary"; then
  while read x;
  do
    name=$(echo "${x}" | cut -d , -f 1 | sed -e "s/'//g")
# The final array schema:
    s=$(echo ${x} | sed -e "s/.*</</" | sed -e "s/'.*//g")
# The unpack array schema:
    u=$(iquery -ocsv -aq "show('unpack(input(${s},\'/dev/null\'),__row)','afl')" | sed 1d | sed -e "s/.*</</" | tr -d "'")
    a=$(echo "${u}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    query="store(redimension(input(${u},'${path}${name}',${NODES},'${fmt}'),${s}),${name})"
    echo "Restoring array ${name}"
    iquery -naq "${query}"
  done < ${mpath}.manifest
  exit 0
fi

if test "${1}" != "restore-opaque"; then
  echo "${usage}"
  exit 3
fi

# Restore array data (opaque case)
while read line; do
  x=$(echo ${line} | cut -d , -f 1 | sed -e "s/'//g")
  s=$(echo ${line} | sed -e "s/.*</</" | sed -e "s/'.*//g")
  echo "Restoring array ${x}"
  iquery -naq "remove(${x})" 2>/dev/null
  iquery -naq "store(input(${s}, '${path}${x}', ${NODES}, 'opaque'),${x})"
done < "${mpath}.manifest"
