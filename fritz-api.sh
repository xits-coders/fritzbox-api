#!/bin/bash
#
# Thanks to http://blog.gmeiners.net/2013/09/fritzbox-mit-nagios-uberwachen.html# for the basis of the original script
#

RC_OK=0
RC_WARN=1
RC_CRIT=2
RC_UNKNOWN=3
HOSTNAME=fritz.box
CHECK=bandwidthdown
CURL=/usr/bin/curl
#todo Do JSON output
#todo fix upstream function displaying other rates (b, k,m)
#todo fix downstream function displaying other rates (b, k,m)

usage()
{
    echo "usage: fritzbox-api.sh -d -h hostname -f <function> [-b rate]"
    echo "    -d: enable debug output"
    echo "    -b: rate to display. b, k, m. all in bits"
    echo "    -j: JSON output. Does not accept any functions. Will display all output in json format. Useful for running in cron and ingesting into another program"
    echo " "
    echo "functions:"
    echo "    linkuptime = connection time in seconds."
    echo "    connection = connection status".
    echo "    upstream   = maximum upstream on current connection (Upstream Sync)."
    echo "    downstream = maximum downstream on current connection (Downstream Sync)."
    echo "    bandwidthdown = Current bandwidth down"
    echo "    bandwidthup = Current bandwidth up"
    echo "    totalbwdown = total downloads"
    echo "    totalbwup = total uploads"
    echo "Default with no added parameters"
    exit ${RC_UNKNOWN}
}

require_number()
{
    VAR=$1
    MSG=$2

    if [[ ! "${VAR}" =~ ^[0-9]+$ ]] ; then
        echo "ERROR - ${MSG} (${VAR})"
        exit ${RC_UNKNOWN}
    fi
}

find_xml_value()
{
    XML=$1
    VAL=$2

    echo "${XML}" | grep "${VAL}" | sed "s/<${VAL}>\([^<]*\)<\/${VAL}>/\1/"
}

check_greater()
{
    VAL=$1
    WARN=$2
    CRIT=$3
    MSG=$4

    if [ ${VAL} -gt ${WARN} ] || [ ${WARN} -eq 0 ]; then
        echo "OK - ${MSG}"
        exit ${RC_OK}
    elif [ ${VAL} -gt ${CRIT} ] || [ ${CRIT} -eq 0 ]; then
        echo "WARNING - ${MSG}"
        exit ${RC_WARN}
    else
        echo "CRITICAL - ${MSG}"
        exit ${RC_CRIT}
    fi
}

print_json(){
   echo "hey"
    VERB1=GetStatusInfo
    URL1=WANIPConn1
    NS1=WANIPConnection

    VERB2=GetCommonLinkProperties
    URL2=WANCommonIFC1
    NS2=WANCommonInterfaceConfig

    VERB3=GetAddonInfos
    URL3=WANCommonIFC1
    NS3=WANCommonInterfaceConfig

    STATUS1=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL1}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS1}:1#${VERB1}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB1} xmlns:u="urn:schemas-upnp-org:service:${NS1}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        echo "ERROR - Could not retrieve status from FRITZ!Box"
        exit ${RC_CRIT}
    fi


    STATUS2=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL2}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS2}:1#${VERB2}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB2} xmlns:u="urn:schemas-upnp-org:service:${NS2}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        echo "ERROR - Could not retrieve status from FRITZ!Box"
        exit ${RC_CRIT}
    fi

    STATUS3=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL3}" \
        -H "Content-Type: text/xml; charset="utf-8"" \
        -H "SoapAction:urn:schemas-upnp-org:service:${NS3}:1#${VERB3}" \
        -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB3} xmlns:u="urn:schemas-upnp-org:service:${NS3}:1" /> </s:Body> </s:Envelope>" \
        -s`

    if [ "$?" -ne "0" ]; then
        echo "ERROR - Could not retrieve status from FRITZ!Box"
        exit ${RC_CRIT}
    fi

    if [ ${DEBUG} -eq 1 ]; then
        echo "DEBUG - Status:"
        echo "${STATUS1}"
        echo "${STATUS2}"
        echo "${STATUS3}"
    fi
    
}

PORT=49000
DEBUG=0
WARN=0
CRIT=0
RATE=1
PRE=bytes

while getopts h:jf:db: OPTNAME; do
    case "${OPTNAME}" in
    h)
        HOSTNAME="${OPTARG}"
        ;;
    j)
        CHECK=""
        DEBUG=1
        print_json
        ;;
    f)
        CHECK="${OPTARG}"
        ;;
    d)
        DEBUG=1
        ;;
    b)
        case "${OPTARG}" in
        b)
            RATE=1
            PRE=bytes
            ;;
        k)
            RATE=1000
            PRE=kilobytes
            ;;
        m)
            RATE=1000000
            PRE=megabytes
            ;;
        *)
            echo "Wrong prefix"
            ;;
        esac
        ;;
    *)
        echo $OPTNAME
        usage
        ;;
    esac
done

case ${CHECK} in
    linkuptime|connection)
        VERB=GetStatusInfo
        URL=WANIPConn1
        NS=WANIPConnection
        ;;
    downstream|upstream)
        VERB=GetCommonLinkProperties
        URL=WANCommonIFC1
        NS=WANCommonInterfaceConfig
        ;;
    bandwidthup|bandwidthdown|totalbwup|totalbwdown)
        VERB=GetAddonInfos
        URL=WANCommonIFC1
        NS=WANCommonInterfaceConfig
        ;;
    *)
        echo "ERROR - Unknown service check ${CHECK}"
        exit ${RC_UNKNOWN}
        ;;
esac

STATUS=`curl "http://${HOSTNAME}:${PORT}/igdupnp/control/${URL}" \
    -H "Content-Type: text/xml; charset="utf-8"" \
    -H "SoapAction:urn:schemas-upnp-org:service:${NS}:1#${VERB}" \
    -d "<?xml version='1.0' encoding='utf-8'?> <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'> <s:Body> <u:${VERB} xmlns:u="urn:schemas-upnp-org:service:${NS}:1" /> </s:Body> </s:Envelope>" \
    -s`

if [ "$?" -ne "0" ]; then
    echo "ERROR - Could not retrieve status from FRITZ!Box"
    exit ${RC_CRIT}
fi

if [ ${DEBUG} -eq 1 ]; then
    echo "DEBUG - Status:"
    echo "${STATUS}"
fi

case ${CHECK} in
linkuptime)
    UPTIME=$(find_xml_value "${STATUS}" NewUptime)
    require_number "${UPTIME}" "Could not parse uptime"

    HOURS=$((${UPTIME}/3600))
    MINUTES=$(((${UPTIME}-(${HOURS}*3600))/60))
    SECONDS=$((${UPTIME}-(${HOURS}*3600)-(${MINUTES}*60)))

    RESULT="Link uptime ${UPTIME} seconds (${HOURS}h ${MINUTES}m ${SECONDS}s)"

    check_greater ${UPTIME} 1 0 "${RESULT}"
    ;;
upstream)
    UPSTREAM=$(find_xml_value "${STATUS}" NewLayer1UpstreamMaxBitRate)
    require_number "${UPSTREAM}" "Could not parse upstream"

    RESULT="Upstream ${UPSTREAM} bits per second"

    check_greater ${UPSTREAM} ${WARN} ${CRIT} "${RESULT}"
    ;;
downstream)
    DOWNSTREAM=$(find_xml_value "${STATUS}" NewLayer1DownstreamMaxBitRate)
    require_number "${DOWNSTREAM}" "Could not parse downstream"

    RESULT="Downstream ${DOWNSTREAM} bits per second"

    check_greater ${DOWNSTREAM} ${WARN} ${CRIT} "${RESULT}"
    ;;
bandwidthdown)
    BANDWIDTHDOWNBITS=$(find_xml_value "${STATUS}" NewByteReceiveRate)
    #BANDWIDTHDOWN=$((BANDWIDTHDOWNBITS/RATE))
    BANDWIDTHDOWN=$(echo "scale=3;$BANDWIDTHDOWNBITS/$RATE" | bc)
    RESULT="Current download ${BANDWIDTHDOWN} ${PRE} per second"
    echo "${RESULT}"
    #check_greater ${BANDWIDTHDOWN} ${WARN} ${CRIT} "${RESULT}"
    ;;
bandwidthup)
    BANDWIDTHUPBITS=$(find_xml_value "${STATUS}" NewByteSendRate)
    BANDWIDTHUP=$(echo "scale=3;$BANDWIDTHUPBITS/$RATE" | bc)
    RESULT="Current upload ${BANDWIDTHUP} ${PRE} per second"
    echo "${RESULT}"
    #check_greater ${BANDWIDTHUP} ${WARN} ${CRIT} "${RESULT}"
    ;;
totalbwdown)
    TOTALBWDOWNBITS=$(find_xml_value "${STATUS}" NewTotalBytesReceived)
    #TOTALBWDOWN=$((TOTALBWDOWNBITS/RATE))
    TOTALBWDOWN=$(echo "scale=3;$TOTALBWDOWNBITS/$RATE" | bc)
    RESULT="total download ${TOTALBWDOWN} ${PRE}"
    check_greater ${TOTALBWDOWN} ${WARN} ${CRIT} "${RESULT}"
    ;;
totalbwup)
    TOTALBWUPBITS=$(find_xml_value "${STATUS}" NewTotalBytesSent)
    #TOTALBWUP=$((TOTALBWUPBITS/RATE))
    TOTALBWUP=$(echo "scale=3;$TOTALBWUPBITS/$RATE" | bc)
    RESULT="total uploads ${TOTALBWUP} ${PRE}"
    check_greater ${TOTALBWUP} ${WARN} ${CRIT} "${RESULT}"
    ;;
connection)
    STATE=$(find_xml_value "${STATUS}" NewConnectionStatus)
    case ${STATE} in
    Connected)
        echo "OK - Connected"
        exit ${RC_OK}
        ;;
    Connecting | Disconnected)
        echo "WARNING - Connection lost"
        exit ${RC_WARN}
        ;;
    *)
        echo "ERROR - Unknown connection state ${STATE}"
        exit ${RC_UNKNOWN}
        ;;
    esac
    ;;
*)
    echo "ERROR - Unknown service check ${CHECK}"
    exit ${RC_UNKNOWN}
esac