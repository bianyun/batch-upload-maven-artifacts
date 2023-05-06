#!/usr/bin/env bash

#============================================
# batch-upload-maven-artifacts.sh
#============================================
# @author bianyun (http://github.com/bianyun)
# @since 2023/3/5
# @version 1.1-SNAPSHOT
#============================================


if [ "$#" -ne 3 ]; then
  echo -e "\033[1;32mUsage: ./batch-upload-maven-artifacts <artifactsDirPath> <repositoryId> <repositoryUrl>\033[m"
  echo ""
  echo "       artifactsDirPath: The dir path containing the artifacts to be uploaded (path must includes 'repository'), "
  echo "                         such as '~/.m2/repository/org/.../', or '~/.m2/repository_bak/org/.../'."
  echo ""
  echo "       repositoryId:     The repositoryId from the <server> configured for the repositoryUrl in settings.xml."
  echo "                         Ensure that you have configured username and password in settings.xml."
  echo ""
  echo "       repositoryUrl:    The URL of the repository where you want to upload the files,"
  echo "                         such as 'http://127.0.0.1:8081/repository/maven-releases/'."
  echo ""
  exit 1
fi

ls $1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "\033[1;31m The artifacts dir path you input does not exits: [$1]\033[m\n" && exit 1
fi

if [[ $1 != *repository* ]]; then
  echo -e "\033[1;31m The artifacts dir path must includes 'repository': [$1]\033[m\n" && exit 1
fi

calc_percentage() {
  local current=$1
  local total=$2
  
  if [[ $current -eq $total ]]; then
    if [[ $total -lt 10000 ]]; then
      echo "100.0%"
    elif [[ $total -ge 10000 ]]; then
      echo "100.00%"
    else
      echo "100.000%"
    fi
  else
    if [[ $total -lt 10000 ]]; then
      awk "BEGIN{print 100*$current/$total}" | awk '{printf "%5.2f%", $1}'; 
    elif [[ $total -ge 10000 ]]; then
      awk "BEGIN{print 100*$current/$total}" | awk '{printf "%6.3f%", $1}'; 
    else
      awk "BEGIN{print 100*$current/$total}" | awk '{printf "%7.4f%", $1}'; 
    fi
  fi
}

build_progress_bar() {
  local current=$1
  local total=$2
  
  local percentage=$(calc_percentage $current $total)
  local detail_progress=$(printf "%2s/$2" $1)
  
  if [[ $total -gt 0 && $total -lt 10 ]]; then
    detail_progress=$(printf "%s/$total" $current)
  elif [[ $total -ge 10 && $total -lt 100 ]]; then
    detail_progress=$(printf "%2s/$total" $current)
  elif [[ $total -ge 100 && $total -lt 1000 ]]; then
    detail_progress=$(printf "%3s/$total" $current)
  elif [[ $total -ge 1000 && $total -lt 10000 ]]; then
    detail_progress=$(printf "%4s/$total" $current)
  else
    detail_progress=$(printf "%5s/$total" $current)
  fi
  echo "$percentage | $detail_progress"
}

calc_total_artifacts_count() {
  >&2 echo -e "\n\033[1;32m=== Start to count the num of artifacts need uploaded, may take a long time, be patient!\033[m"
  
  local artifactsDirPath="$1"
  >&2 echo "artifactsDirPath=$artifactsDirPath"

  local count=0
  while read -r line ; do
    if [[ $line == *-SNAPSHOT* ]]; then
      continue
    fi
    count=$((count+1))
  done < <(find $artifactsDirPath -type f -name "*.pom")
  echo $count
}

make_seconds_human_readable() {
  local seconds=$1
  
  local day=$(( $seconds/86400 ))
  local hour=$(( ($seconds-$day*86400)/3600 ))
  local min=$(( ($seconds-$day*86400-$hour*3600)/60 ))
  local sec=$(( $seconds-$day*86400-$hour*3600-$min*60 ))
  
  local result=""
  
  if [[ $day -gt 0 ]]; then
    result="${day}d ${hour}h ${min}m ${sec}s"
  elif [[ $day -eq 0 ]]; then
    if [[ $hour -gt 0 ]]; then
      result="${hour}h ${min}m ${sec}s"
    elif [[ $hour -eq 0 ]]; then
      if [[ $min -gt 0 ]]; then
        result="${min}m ${sec}s"
      elif [[ $min -eq 0 ]]; then
        result="${sec}s"
      fi
    fi
  fi
  
  if [[ $day -gt 0 ]]; then
    local compactFormat=$(printf "(%dd:%02d:%02d:%02d)" $day $hour $min $sec)
  else
    local compactFormat=$(printf "(%02d:%02d:%02d)" $hour $min $sec)
  fi
  
  echo "$result $compactFormat"
}

upload_artifacts() {
  local artifactsDirPath="$1"
  local repositoryId="$2"
  local repositoryUrl="$3"
  
  local totalCount=$(calc_total_artifacts_count "$artifactsDirPath")
  echo -e "\n\033[1;35m=== Start to upload artifacts (total count: $totalCount)...\033[m\n"
  
  local index=0
  while read -r line ; do
    if [[ $line == *-SNAPSHOT* ]]; then
      continue
    fi
    
    local pomFilePath="$(realpath $line)"
    local commonPrefix="${pomFilePath/.pom/}"
    local jarFileWildCardPath="${commonPrefix}*.jar"
    local extraJarFileWildCardPath="${commonPrefix}-*.jar"
    
    local jarFilePath="${commonPrefix}.jar"
    local javadocFilePath="${commonPrefix}-javadoc.jar"
    local sourcesFilePath="${commonPrefix}-sources.jar"
    
    index=$((index+1))
    local progressBar=$(build_progress_bar $index $totalCount)
    local artitactPath="$(echo $pomFilePath | sed 's/^.*\/repository[^/]*\/\(.*\)$/\1/')"
    
    local totalJarFileCount=$(ls $jarFileWildCardPath 2>/dev/null |wc -l)
    local extraJarFileClassifiers=$(ls $extraJarFileWildCardPath 2>/dev/null |grep -v javadoc |grep -v sources |sed 's/.*-//g' |sed 's/.jar//g' |tr '\n' ' ')
    local extraJarFileCount=$(echo $extraJarFileClassifiers |wc -w)
    
    local baseDeployCmd="mvn -q deploy:deploy-file -DpomFile=$pomFilePath -DrepositoryId=$repositoryId -Durl=$repositoryUrl"
    local deployCmd=""
    
    if [ $totalJarFileCount -eq 0 ]; then
      deployCmd="$baseDeployCmd -Dfile=$pomFilePath"
      eval $deployCmd || exit 1
    else
      if [[ $extraJarFileCount -gt 0 ]]; then
        for classifier in $extraJarFileClassifiers; do
          local extraJarFile="${commonPrefix}-${classifier}.jar"
          deployCmd="$baseDeployCmd -Dfile=$extraJarFile -Dclassifier=$classifier"
          eval $deployCmd  || exit 1
        done
        
        artitactPath="${artitactPath/.pom/}"
        artitactPath="${artitactPath/.jar/}"
        if [[ $extraJarFileCount -eq 1 ]]; then
          artitactPath="${artitactPath}-$(echo $extraJarFileClassifiers).jar"
        else
          artitactPath="${artitactPath}-[$(echo $extraJarFileClassifiers | tr ' ' ',')].jar"
        fi
      fi

      if [[ -f $jarFilePath ]]; then
        deployCmd="$baseDeployCmd -Dfile=$jarFilePath"
        if [[ -f $javadocFilePath ]]; then
          deployCmd="$deployCmd -Djavadoc=$javadocFilePath"
        fi
        if [[ -f $sourcesFilePath ]]; then
          deployCmd="$deployCmd -Dsources=$sourcesFilePath"
        fi
        
        artitactPath="$(echo $jarFilePath | sed 's/^.*\/repository[^/]*\/\(.*\)$/\1/')"
        
        eval $deployCmd || exit 1
      fi
      
    fi
    
    echo -e "\033[1;34m[$progressBar] - [ $artitactPath ]\033[m"
  done < <(find $artifactsDirPath -type f -name "*.pom")
}

startSeconds=$(date +%s)

upload_artifacts "$1" $2 $3

endSeconds=$(date +%s)
totalSeconds=$((endSeconds - startSeconds))

totalTime=$(make_seconds_human_readable $totalSeconds)

echo -e "\n\033[1;32m=== All has been done successfully!\033[m \033[1;36mTotal time: $totalTime\033[m\n"
