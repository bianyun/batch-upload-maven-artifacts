#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
  echo "Usage: ./upload_to_local_nexus.sh <artifacts-dir-path>"
  echo ""
  echo "       artifactsDirPath: The dir path containing the artifacts to be uploaded (path must includes 'repository'), "
  echo "                         such as '~/.m2/repository/org/.../', or '~/.m2/repository_bak/org/.../'."
  echo ""
  exit 1
fi

./batch-upload-maven-artifacts.sh "$1" local-nexus-release http://127.0.0.1:8081/repository/maven-releases