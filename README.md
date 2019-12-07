# actionEngine
New Relic OHI that provides a method for executing scripts or commands locally as a response to a New Relic Alert Policy Incident.

# Overview:
The solution is driven off of events inserted into the "Alerts" event table in Insights.  The events in the Alerts table identify the incident that has opened, and the desired action (script or command) to be executed on the host.  Creating a webhook as anotifcation channel allows you to generate these events.

The actionEngine.pl OHI script polls open incidents, validates that they are enabled, that they are specific to the host running the OHI, and that the desired action has not been prevsiously executed.  If all is true the action is executed, recorded as exectuted locally, and the results are posted to Insights.

The method of identifying actions which have been executed is by means of "checkpoint" files.  Checkpoint files have a filename of "checkpoint.incidentID" . Where incidentID is the New Relic incident ID.  These files are purged once they are greater than 30 minutes old.

# Setup:
1. Place actionEngine.pl and action-engine.yml in /var/db/newrelic-infra/custom-integraitons.  Make sure the scrpt has execute permissions
2. Place action-engine-config.yml in /etc/newrelic-infra/integrations.d
3. Edit actionEngine.pl modifying the following variables within the init subroutine, replacing "CHANGE-ME" with your RPM ID, and Insights query key.
- rpmId
- insightsKey
4. Create the webhook that will populate the Alerts table in Insights that will define the local actions.  Create a standard webhook notification channel, select the "custom JSON" option and insert the following two elements:
  - "eventType": "Alerts",
  - "action_policy": "true",
  - "action_policy_desc": "Describe the action to be taken or the policy etc",
  - "action_policy_exec": "system command or script to be executed",
    - "eventType" is required to be set to the value of "Alerts"
    - "action_policy" is an enablement toggle, true indicates the policy will be executed, false it will not.  This provides a way to possibly temporarily disable the action policy.
    - "action_policy_desc" is just a place where you can insert any ddescription that might be relevant.
    - "action_policy_exec" The script or command to be executed, not that scripts will require the full path, interpretted languages may need to be prefixed with the interpreter (ie: perl somePerlScript.pl).  Commands can be included as they would be executed via command line.
5. Restart the infrastructure agent.

# Troubleshooting:
While testing it might make sense to set the solution in debug mode and supress the OHI JSON.  Setting the OHIMode variabl in the init subroutine to "0" will supress OHI output.  Setting the debugMode variable in the init subroutine to "1" will increase verbosity and provide additional debugging output.  Feel free to reach out, this is a prototype, working in my account but I'm happy to help if there are use cases requiring changes or you need some assistance.
