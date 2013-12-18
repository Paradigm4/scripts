#!/bin/bash
#
# A basic script that backs up SciDB databases to files and reloads them.
# Run this script from the coordinator instance. The script uses iquery
# and assumes it is available in the PATH.

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

Remove backup data and directories (warning!)
./scidb_backup.sh remove_backup_dirs <directory>

If the backup directory does not already exist, then it will be created.

Set the optional parallel flag to 1 to indicate parallel save/load. Then the
data directory is assumed to be a subdirectory of each of the SciDB instance
data directories. Note that parallel save requires ssh access to each SciDB
node to set up the directories.

If the parallel flag is not specified or not set to 1, then the backup data
are saved to the specified directory path on the coordinator instance.

The script assumes that SciDB is running on its default port.

The opaque methods are faster and more general, but sometimes the opaque
save format does not work between SciDB versions. In such cases, use the
binary methods.
eof

NODES="0"

[ $# -lt 2 ] && echo "${usage}" && exit 1

if test $# -gt 2; then
# Parallel save/load
  NODES="-1"
  path="${2}/"
# In this case, the manifest is only stored on the coordinator.
  mpath="$(iquery -ocsv -aq "list('instances')" | sed -n 2p | sed -e "s/.*,//" | tr -d "'")/"
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

create_dirs ()
{
  iquery -ocsv -aq "list('instances')" | sed 1d | while read line; do
    instance=$(echo $line | sed -e "s/,.*//" | tr -d "'")
    ipath="$(echo $line | sed -e "s/.*,//" | tr -d "'")/$1"
    echo "ssh $instance \"mkdir -p ${ipath}\""
    ssh $instance "mkdir -p ${ipath}" &
  done
  wait
}

if test "${1}" == "delete_backup_dirs"; then
  iquery -ocsv -aq "list('instances')" | sed 1d | while read line;
  do
    instance=$(echo $line | sed -e "s/,.*//" | tr -d "'")
    ipath="$(echo $line | sed -e "s/.*,//" | tr -d "'")/$1"
    echo "ssh $instance \"rm -rf ${ipath}\""
    ssh $instance "rm -rf ${ipath}" &
  done
  wait
  exit 0
fi

# Backup array data
if test "${1}" == "save-opaque"; then
  [ "${NODES}" == "-1" ] && create_dirs ${path}
  iquery -ocsv -aq "list('arrays')" | sed 1d > ${mpath}.manifest
  a=$(cat ${mpath}.manifest | cut -d , -f 1 | sed -e "s/'//g")
  for x in ${a};do
    echo "Archiving array ${x}"
    iquery -naq "save(${x}, '${path}${x}', ${NODES}, 'opaque')"
  done
  exit 0
fi

if test "${1}" == "save-binary"; then
  [ "${NODES}" == "-1" ] && create_dirs ${path}
  iquery -ocsv -aq "list('arrays')" | sed 1d > ${mpath}.manifest
  while read x;
  do
    name=$(echo "${x}" | cut -d , -f 1 | sed -e "s/'//g")
    a=$(echo "${x}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    query="save(${name}, '${path}${name}', ${NODES}, '${fmt}')"
    echo "Archiving array ${name}"
    iquery -naq "${query}"
  done < ${mpath}.manifest
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
    s=$(echo ${x} | sed -e "s/.*</</" | sed -e "s/'.*//g")
    a=$(echo "${x}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    query="store(input(${s},'${path}${name}',${NODES},'${fmt}'),${name})"
    echo "Restoring array ${name}"
    iquery -naq "${query}"
  done < ${mpath}.manifest
  exit 0
fi

if test "${1}" != "restore-opaque"; then
  echo ${usage}
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
