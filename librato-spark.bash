#!/usr/bin/env bash
##
## librato-spark
## https://github.com/librato/librato-spark/
##
## Retrieves data from a metric stored in Librato Metrics and sends it to
## spark (https://github.com/holman/spark/) to generate sparklines.
## 
## Examples:
##   librato-spark cpu
##   librato-spark cpu -s i-6b546b05
##   librato-spark cpu -d 120
##   librato-spark requests.per.second -b 
## 

SPARK_URL="https://github.com/holman/spark/"
METRICS_URL="https://metrics.librato.com/"
METRICS_API_URL="${METRICS_URL}/metrics-api/v1/metrics"

## Print out usage information
usage () {
  echo
  echo "  USAGE: ${0} <metric> [-s source] [-d duration] [-b] [-u] [-v]"
  echo

  echo
  echo "  EXAMPLE: ${0} cpu"
  echo "  Fetch data from the metric named \"cpu\"."
  echo "  Do not limit the data fetched to any particular source"
  echo "  Fetch 60 minutes worth of data"
  echo "  Present the sum of all sources as a single sparkline."
  echo

  echo
  echo "  EXAMPLE: ${0} cpu -s i-6b546b05"
  echo "  Limit the data to only measurements with source of \"i-6b546b05\""
  echo "  DEFAULT: *"
  echo

  echo
  echo "  EXAMPLE: ${0} cpu -d 600"
  echo "  Fetch any available data for \"cpu\" from the last 10 minutes only."
  echo "  DEFAULT: 3600"
  echo

  echo
  echo "  EXAMPLE: ${0} cpu -b"
  echo "  If there are multiple sources for \"cpu\" print a sparkline for each one."
  echo "  DEFAULT: Print multiple sources as a single sparkline"
  echo

  echo
  echo "  EXAMPLE: ${0} cpu -v"
  echo "  If there are multiple sources for \"cpu\" print a sparkline for each one."
  echo "  DEFAULT: Print multiple sources as a single sparkline"
  echo

  echo
  echo "  EXAMPLE: ${0} cpu -u"
  echo "  Print a URL that can be loaded in a web browser for the Metric."
  echo "  To automatically open this URL on MacOS: export LIBRATO_SPARK_URL_OPEN=true"
  echo "  DEFAULT: Do not print the URL of the Metric"
  echo

  echo
}


## If we didn't get any command line options provide usage information.
if [ -z ${1} ]; then
  usage
  exit 1;
fi

## What is the name of the metric?
METRIC_NAME=$1
shift

## If the METRIC_NAME looks like it starts with a "-" throw a usage error as we probably
## received an option, rather than a metric name as the first argument
echo $METRIC_NAME | grep '^-' &>/dev/null
if [ $? -eq 0 ]; then
  usage
  exit 1;
fi


## Set the defaults for the options
LIBRATO_SPARK_SOURCE="*"
LIBRATO_SPARK_DURATION="3600"
LIBRATO_SPARK_BREAKOUT="FALSE"
LIBRATO_SPARK_PRINT_URL="FALSE"
LIBRATO_SPARK_VERBOSE="FALSE"

## Check for the various options and print usage if arguments missing or
## options are unknown.
while getopts ":s:d:bu" opt; do
  case ${opt} in
    s)
      #echo "source is ${OPTARG}" >&2
      LIBRATO_SPARK_SOURCE="${OPTARG}"
      ;;
    d)
      #echo "duration is ${OPTARG}" >&2
      LIBRATO_SPARK_DURATION="${OPTARG}"
      ;;
    b)
      #echo "One sparkline per source" >&2
      LIBRATO_SPARK_BREAKOUT="TRUE"
      ;;
    u)
      #echo "Print URL" >&2
      LIBRATO_SPARK_PRINT_URL="TRUE"
      ;;
    \?)
      echo
      echo "Unknown option: -${OPTARG}" >&2
      usage
      exit 1
      ;;
    :)
      echo
      echo "Option -${OPTARG} requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done


## Check for required Librato Metrics API Credentials
if [ -z ${LIBRATO_USERID} ]; then
  echo
  echo "ERROR: The environment variable LIBRATO_USERID must be set."
  echo "       Both LIBRATO_USERID and LIBRATO_API_TOKEN must be defined."
  echo
  exit 2;
fi
if [ -z ${LIBRATO_API_TOKEN} ]; then
  echo
  echo "ERROR: The environment variable LIBRATO_API_TOKEN must be set."
  echo "       Both LIBRATO_API_TOKEN and LIBRATO_USERID must be defined."
  echo
  exit 2;
fi

## Is spark installed somewhere such that we can run it?
spark >/dev/null 2>&1 || {
  echo
  echo "ERROR: I can't execute the command \"spark\"! Terminating."
  echo
  echo "       librato-spark uses spark to draw the sparklines"
  echo
  echo "       Please verify that spark is executable in your environment"
  echo "       ${SPARK_URL}"
  echo
  exit 3;
}



## If we don't know how to process this metric type throw an error.
exit_if_metric_type_unsupported() {
  ## Get the type, to make sure we are sending the right kind of query

  METRIC_TYPE_CURL_OUTPUT=`curl              \
    --silent                                 \
    -u $LIBRATO_USERID:$LIBRATO_API_TOKEN    \
    -d 'max_sources=1'                       \
    -X GET ${METRICS_API_URL}/${METRIC_NAME}`

  ## Send stderr to null while having python parse the data. There is
  ## no need to send a big python error to the screen in the event of
  ## a bad metric name or other typo.
  METRIC_TYPE=`echo ${METRIC_TYPE_CURL_OUTPUT} \
  | python -c 'import sys,json;response=json.loads(sys.stdin.read()); print json.dumps(response["type"])' 2> /dev/null  \
  | cut -f2 -d'"'`

  case "${METRIC_TYPE}" in
    gauge)
      SUMMARIZE_OPTIONS='-d summarize_sources=true'
      ;;
    counter)
      ## Summarization of counters is not yet supported
      SUMMARIZE_OPTIONS=''
      ;;
    *)
      echo
      echo "ERROR: We could not make sense of the response. Does the metric \"${METRIC_NAME}\" exist?"
      echo
      exit 2
      ;;
  esac
}


## Echo the raw result of the CURL back so we can store it for
## repeated processing as necessary.
fetch_metric_into_variable() {
  NOW=`date +"%s"`
  THEN=$((NOW - ${LIBRATO_SPARK_DURATION}))

  ## Store this so we can evaluate it more than once later on.
  CURL_OUTPUT=`curl                            \
    --silent                                   \
    -u $LIBRATO_USERID:$LIBRATO_API_TOKEN      \
    -d "resolution=1"                          \
    -d "start_time=$THEN"                      \
    -d   "end_time=$NOW"                       \
    -d "max_sources=50"                        \
    -d "sources%5B%5D=${LIBRATO_SPARK_SOURCE}" \
    ${SUMMARIZE_OPTIONS}                       \
    -X GET ${METRICS_API_URL}/${METRIC_NAME}`
}


## While there are arguments left to process
## send the CURL_OUTPUT (JSON) through a process
## that rips the JSON text into a string of values.
## Turn each value into a neline
## Remove leading whitespace
## Pull out only the lines with the data we care
## about, which might be value, sum or delta.
## Get only the value (including any decimal places)
## Turn those lines of data into a single line
## Pipe that data to spark.
print_sparkline() {
  while (( "$#" )); do
    ## Extract the measurements for the source that we are working
    ## on right now:
    SOURCE_DATA=`echo ${CURL_OUTPUT} \
      | python -c "import sys,json;response=json.loads(sys.stdin.read()); print json.dumps(response['measurements'][\"$1\"])"`

    SPARK_OUTPUT=`echo ${SOURCE_DATA} \
      | tr "," "\n" \
      | sed "s/^ *//" \
      | grep "^\"${GREP_TERM}\":" \
      | cut -f2 -d':' \
      | sed 's/[^.0-9]//g' \
      | xargs \
      | spark`
    echo -n ${SPARK_OUTPUT}
    echo "  $1"

    ## If the user wanted to see a printed URL print that as well
    if [ "${LIBRATO_SPARK_PRINT_URL}" == "TRUE" ]; then
      PRINTED_URL="${METRICS_URL}/metrics/${METRIC_NAME}"
      echo "${PRINTED_URL}"

      ## If they also wanted to have that URL opened for them 
      if ! [ -z ${LIBRATO_SPARK_URL_OPEN} ]; then
         ## If we are on a Darwin system where this is possible
        if [ "`uname -s`" == "Darwin" ]; then
          open ${PRINTED_URL}
        else
          echo "URL opening is only supported on MacOS X."
        fi
      fi
    fi

    shift
  done
}


## Set by exit_if_metric_type_unsupported once the METRIC_TYPE is determined
SUMMARIZE_OPTIONS=""
GREP_TERM=""

## Don't do the second query until we know we support this metric type
exit_if_metric_type_unsupported

## Now that we know we have a gauge, use the gauge specific options to fetch
## all the sources and summarize them together.
fetch_metric_into_variable

## Get the list of sources from the CURL_OUTPUT
SOURCES=`echo ${CURL_OUTPUT} \
  | python -c 'import sys,json;response=json.loads(sys.stdin.read()); print "\n".join(response["measurements"].keys());'`

## The source list needs to be modified to match the options and
## METRIC_TYPE:
## Only gauges can be summarized (use "all")
## If breakout is set, only print the indvidual sources rather than "all"
## If the metric is a counter just print any sources that were returned
case "${METRIC_TYPE}" in
  gauge)
    if [ "${LIBRATO_SPARK_BREAKOUT}" == "TRUE" ]; then
      SOURCES=`echo $SOURCES | tr " " "\n" | grep -v '^all$' | sort | xargs`
      GREP_TERM="value"
    else
      SOURCES="all"
      GREP_TERM="sum"
    fi
    ;;
  counter)
    SOURCES=`echo $SOURCES | tr " " "\n" | sort | xargs`
    GREP_TERM="delta"
    ;;
esac

## Print the sparkline!
print_sparkline $SOURCES


exit;

