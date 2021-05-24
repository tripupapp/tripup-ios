#!/bin/sh

#  info_preprocesser_generator.sh
#  TripUp
#
#  Created by Vinoth Ramiah on 19/02/2018.
#  Copyright © 2018 Vinoth Ramiah. All rights reserved.
#
#  IMPORTANT: MUST REFRESH Info.plist file on target manually using a pre-action script!
#  Otherwise changes won't happen on subsequent builds without cleaning product first

# string helper function to find start index of a substring in a string, stackoverflow.com
strindex() {
    x="${1%%$2*}"
    [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
}

preprocess_file="${INFOPLIST_PREFIX_HEADER}"
mkdir -p $(dirname $preprocess_file)    # fixes annoying XCode errors when build directory hasn't been created yet

echo "/*------------------------------------------"     >  $preprocess_file
echo "   Auto generated file. Don't edit manually."     >> $preprocess_file
echo "   See info_preprocesser_generator script"        >> $preprocess_file
echo "   for details."                                  >> $preprocess_file
echo "  ------------------------------------------*/"   >> $preprocess_file
echo ""                                                 >> $preprocess_file

# split API_BASE_URL into its protocol, host and port values
a=$(strindex "${API_BASE_URL}" "://")
protocol=${API_BASE_URL:0:$a}
b=$(($a + 3))
host_port=${API_BASE_URL:$b}
c=$(strindex "$host_port" ":")
if [ $c = -1 ]; then
    host=$host_port
    port=80
else
    host=${host_port:0:$c}
    port=${host_port:$c+1}
fi

# If host portion of API_BASE_URL is "localhost", use the Mac's local network name instead.
# This allows physical devices to connect to the local machine as "localhost" will fail on
# actual devices
if [ $host = localhost ]; then
    host=$(scutil --get LocalHostName | tr "[:upper:]" "[:lower:]").local
    echo "#define   API_HOST    $protocol://$host:$port"    >> $preprocess_file
else
    echo "#define   API_HOST    ${API_BASE_URL}"            >> $preprocess_file
fi
