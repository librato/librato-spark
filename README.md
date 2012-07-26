librato-spark
=============

Command line interface to generate sparklines of your Librato metrics



    LIBRATO_USERID="email address you registered with"
    LIBRATO_API_TOKEN="l809ejfjsdf909009237754blkoe2907708"

The default behavior is to look for the last 3600 seconds, or 60 minutes worth of data and present that as a single summarized sparkline:

    ./librato-spark.bash api.measures.posts.vol.total

If you would prefer to break each source out rather than have it as a single summarized sparkline then give it the -b (breakout) option:

    ./librato-spark.bash nginx-slowest -b

If the metric is a counter it will automatically be given the -b (breakout) option by default:

    ./librato-spark.bash acked_stats

Run the command without any options to get a usage statement:

    USAGE: ./librato-spark.bash <metric> [-s source] [-d duration] [-b] [-u] [-v]
    
    
    EXAMPLE: ./librato-spark.bash cpu
    Fetch data from the metric named "cpu".
    Do not limit the data fetched to any particular source
    Fetch 60 minutes worth of data
    Present the sum of all sources as a single sparkline.
    
    
    EXAMPLE: ./librato-spark.bash cpu -s i-6b546b05
    Limit the data to only measurements with source of "i-6b546b05"
    DEFAULT: *
    
    
    EXAMPLE: ./librato-spark.bash cpu -d 600
    Fetch any available data for "cpu" from the last 10 minutes only.
    DEFAULT: 3600
    
    
    EXAMPLE: ./librato-spark.bash cpu -b
    If there are multiple sources for "cpu" print a sparkline for each one.
    DEFAULT: Print multiple sources as a single sparkline
    
    
    EXAMPLE: ./librato-spark.bash cpu -v
    If there are multiple sources for "cpu" print a sparkline for each one.
    DEFAULT: Print multiple sources as a single sparkline
    
    
    EXAMPLE: ./librato-spark.bash cpu -u
    Print a URL that can be loaded in a web browser for the Metric.
    To automatically open this URL on MacOS: export LIBRATO_SPARK_URL_OPEN=true
    DEFAULT: Do not print the URL of the Metric
    
    
