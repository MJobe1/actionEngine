#!/usr/bin/perl
#+--------------------------------------------------------------+
#| Name: actionEngine.pl               Author: Michael Jobe     |
#| Function: Grab Alerts that have been populated with the      |
#|           webhook, check for actions specific to the host    |
#|           executing the OHI, and execute the actions,        |
#|           optionally reporting the results back to Insights. |
#+--------------------------------------------------------------+
use JSON;
use Data::Dumper;
use POSIX qw(strftime);

init();
getAlertIncidents();
processWorkQueue();
checkpointFileCleanup();
exit;

sub init {
#+-----------------------------------------------------------------+
#| Options descriptions:                                           |
#|  Note: These should be yaml config options, and if there is a   |
#|        real customer use case I'll modify this.                 |
#|                                                                 |
#| OHIMode - A setting of "1" (true) will direct the script to     |
#|           output OHI friendly JSON to enable the population     |
#|           of action results back to Insights.                   |
#| debug   - A setting of "1" (true) enables verbose logging to    |
#|           the logfile.                                          |
#| eventtype - The name of the resulting Insights table, this can  |
#|             be changed if needed.                               |
#| checkPointPath - The path of the checkpoint files. The check    |
#|                  point files provide the ability for the script |
#|                  to understand which events have been processed |
#|                  these files are automatically curated and      |
#|                  deleted when not relevant,                     |
#| rpmId - The RPM id you are pulling data from. Note that it is   |
#|         possible to pull data from one RPM and have the infra   |
#|         agent configured to report to a different RPM.          |
#+-----------------------------------------------------------------+
    open (LOGFILE, ">>action-engine.log");
    $OHImode=1;
    $eventtype="ActionResults";
    $debug=0;
    $myHost=`hostname`;
    chomp($myHost);
    $checkPointPath="/var/db/newrelic-infra/custom-integrations/";
    $rpmId="CHANGE-ME";
    $insightsKey="CHANGE-ME";
    debugOut($checkPointFile);
    $header="{\"name\": \"action-engine\", \"protocol_version\": \"1\", \"integration_version\": \"0.0.1\",\"metrics\": [";
    $payload = $payload . "{\"event_type\": \"$eventtype\",";
    $footer="],\"inventory\":{},\"events\":[]}";
    $checkPointPath="/var/db/newrelic-infra/custom-integrations/";
}

#+-----------------------------------------------------------------+
#| getAlertIncidents subroutine.                                   |
#| Purpose: grab all New Relic Incidents for a given RPM.          |
#+-----------------------------------------------------------------+
sub getAlertIncidents {
    $sub="getAlertIncidents";
    if ($debug) { debugOut("SUBROUTINE: getAlertIncidents"); }
    $actionEvents= `curl -s -H "Accept: application/json" -H "X-Query-Key: $insightsKey" "https://insights-api.newrelic.com/v1/accounts/$rpmId/query?nrql=SELECT%20incident_id%2C%20action_policy_exec%2C%20details%20FROM%20Alerts%20where%20action_policy%20%3D%27true%27%20since%2015%20minutes%20ago"`;
    $decodedJSON=decode_json($actionEvents);
#    print Dumper($decodedJSON);
    $eventData=Dumper($decodedJSON);
    @eventData2=split /,/,$eventData;
    if ($debug) { debugOut("\tRequesting Alerts from the last 5 minutes..."); }
    if ($debug) { debugOut("\tRecieved JSON paylod with $#eventData2 elements..."); }
    foreach (@eventData2) {
        $writeArray=0;
        if (m/'timestamp'\s\S+\s'(\d+)'/) {
            $eventTimestamp=$1;
        }
        if (m/'details'\s\S+\s'(.+)'/) {
             ($details,$hostname,$junk)=split /\\/, $1;
             $hostname =~ s/'//;
        }
        if (m/'action_policy_exec'\s\S+\s'(.+)'/) {
             $action=$1;
        }
        if (m/'incident_id'\s\S+\s(\d+)/) {
             $incidentId=$1;
             $checkPointFile=$checkPointPath . "checkpoint." . $incidentId;
             if ($debug) { debugOut("\tFinished gathering elements for Incident_id: $incidentId\n"); }
             if (-e $checkPointFile) {
                $notProcessed=0;
                if ($debug) { debugOut("\tIncident_id: $incidentId has already been processed."); }
                $hostname="";
                $action="";
                $incidentId="";
                $eventTimestamp="";
             }
             else {
             	  $notProcessed=1;
                `touch checkpoint.$incidentId`;
                if ($debug) { debugOut("\tIncident_id: $incidentId has NOT been processed."); }
                $writeArray=1;  # We have a fulll set of elements so write out our arrays...
             }
        }
        if ($notProcessed && $writeArray) {
             if ($debug) { debugOut("\tHost: $hostname"); }
             if ($debug) { debugOut("\tAction: $action"); }
             if ($debug) { debugOut("\tIncident: $incidentId"); }
             $item = $hostname . "::" . $action . "::" . $incidentId . "::" . $eventTimestamp;
             push(@workQueue, $item);
             $writeArray=0;
        }
    }
}
#+-----------------------------------------------------------------+
#| processWorkQueue subroutine.                                    |
#| Purpose: Execute all the actions associated with this host.     |
#+-----------------------------------------------------------------+
sub processWorkQueue {
    $sub="processWorkQueue";
    if ($debug) { debugOut("Executing processWorkQueue....\n") }
    foreach $job (@workQueue) {
        ($hostname,$action,$incidentId,$timestamp)=split('::',$job);
        if ($debug) { debugOut("Processing action item:") }
        if ($debug) { debugOut("Hostname: $hostname") }
        if ($debug) { debugOut("Action: $action") }
        if ($debug) { debugOut("Incident: $incidentId:") }
        if ($debug) { debugOut("Timestamp: $timestamp\n") }
        if ($myHost eq $hostname) {
            if ($debug) { debugOut("Incident: $incidentId is for $myHost") }
            if ($debug) { debugOut("----> Executing: $action") }
            $results = `$action`;
            $rc=$?;
            if ($debug) { debugOut("----> Return Code: $rc") }
            chomp($results);
            if ($debug) { debugOut("----> Output: $results") }
            if ($OHImode) {
                $eventInstance = $eventInstance .
                       "{\"event_type\": \"$eventtype\"," .
                       "\"action_host\": \"$myHost\"," .
                       "\"action_exec\": \"Executed on host: $action\"," .
                       "\"action_rc\": $rc," .
                       "\"incident_id\": \"$incidentId\"," .
                       "\"action_result\": \"$results\"},";
             }
        }
        else {
            if ($debug) { debugOut("Incident: $incidentID is NOT for $myHost\n") }
        }
    }
    if ($OHImode) {
        if ($eventInstance ne "") {
            chop($eventInstance);
            $JSONOutput = $header . $eventInstance . $footer;
            print $JSONOutput;
            print LOGFILE $JSONOutput;
        }
        else {
            debugOut("NOTHING TO SEND!\n");
        }
    }
}
#+-----------------------------------------------------------------+
#| debugOut subroutine.                                            |
#| Purpose: provide a common debug output format.                  |
#+-----------------------------------------------------------------+
sub debugOut {
   $error = $_[0];
   if ($debug) { print $sub . " - " ,"$error\n"; print LOGFILE "$error\n";}
   # $datestring = strftime "%a %b %e %H:%M:%S %Y", localtime;
   # printf LOGFILE "$datestring  -  $error\n";;
}
sub checkpointFileCleanup {
    $sub = "checkpointFileCleanup";
    opendir (DIR, $checkPointPath) || die "Error while opening dir $checkPointPath: $!\n";
    while(my $filename = readdir(DIR)){
        if ($filename =~ m/checkpoint\.(\d+)/) {
            $filename = $checkPointPath . $filename;
            getfilestats($filename);
        }
    }
}
#+-----------------------------------------------------------------+
#| debugOut getFilestats.                                          |
#| Purpose: Because we're dealing with stateless events, we write  |
#|          checkpoint files to identify the inidents we have      |
#|          executed the desired action on.  These files are       |
#|          purged here.                                           |
#+-----------------------------------------------------------------+
sub getfilestats(@) {
    $sub = "getfilestats";
    my($file) = @_;
    my $currtime = time;
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ictime,
    	     $blksize,$blocks) = stat("$file");
                $ictime = $currtime - $ictime;
                $atime = $currtime - $atime;
                $mtime = $currtime - $mtime;
    if ($ictime > 2100) {
         `rm -rf $file`;
    }
}
