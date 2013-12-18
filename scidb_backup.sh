#!/bin/bash
#
# A basic script that backs up SciDB databases to files and reloads them.
# Run this script from the coordinator instance. The script uses iquery
# and assumes it is available in the PATH.

unalias iquery >/dev/null 2>&1
read -d '' usage << "eof"
Save SciDB data with:
./scidb_backup.sh save-opaque <backup directory to save data to>
-or-
./scidb_backup.sh save-binary <backup directory to save data to>

Restore SciDB data with:
./scidb_backup.sh restore-opaque <backup directory containing saved data>
-or-
./scidb_backup.sh restore-binary <backup directory containing saved data>

If the backup directory does not already exist when saving, it will be created.

The opaque methods are faster and more general, but sometimes the opaque
save format does not work between SciDB versions. In such cases, use the
binary methods.
eof

if test $# -lt 2; then
  echo "${usage}"
  exit 1
fi

path=$(readlink -f ${2})
if test ! -d ${path}; then
  mkdir -p ${path} 2>/dev/null
fi
if test ! -d ${path}; then
  echo "${usage}"
  exit 2
fi

# Backup array data
if test "${1}" == "save-opaque"; then
  iquery -ocsv -aq "list('arrays')" | sed 1d > ${path}/.manifest
  a=$(cat ${path}/.manifest | cut -d , -f 1 | sed -e "s/'//g")
  for x in ${a};do
    echo "Archiving array ${x}"
    iquery -naq "save(${x}, '${path}/${x}', 0, 'opaque')"
  done
  exit 0
fi

if test "${1}" == "save-binary"; then
  iquery -ocsv -aq "list('arrays')" | sed 1d > ${path}/.manifest
  while read x;
  do
    name=$(echo "${x}" | cut -d , -f 1 | sed -e "s/'//g")
    a=$(echo "${x}" | sed -e "s/.*<//" | sed -e "s/>.*//")
    fmt="($(echo "${a}" | sed -e "s/:/\n/g" | sed -e "s/,/\n/g" | sed -n 'g;n;p' | sed -e "s/DEFAULT.*//" | tr "\n" "," | sed -e "s/,$//"))"
    query="save(${name}, '${path}/${name}', 0, '${fmt}')"
    echo "Archiving array ${name}"
    iquery -naq "${query}"
  done < ${path}/.manifest
  exit 0
fi

if test ! -f "${path}/.manifest"; then
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
    query="store(input(${s},'${path}/${name}',0,'${fmt}'),${name})"
    echo "Restoring array ${name}"
    iquery -naq "${query}"
  done < ${path}/.manifest
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
  iquery -naq "store(input(${s}, '${path}/${x}', 0, 'opaque'),${x})"
done < "${path}/.manifest"
