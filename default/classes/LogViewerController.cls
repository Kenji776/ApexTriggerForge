public without sharing class LogViewerController {
    @AuraEnabled(cacheable=false)
    public static List<Trigger_Execution_Log__c> getLogs(Id recordId) {

        String sObjectType = recordId.getSObjectType().getDescribe().getName();

        system.debug('Getting logs for record: ' + recordId + ' of type ' + sObjectType);

        sObject recordDetails = database.query('SELECT CreatedDate FROM ' +SObjectType+' WHERE ID = :recordId');
        dateTime timeStamp = (DateTime)recordDetails.get('CreatedDate');

        // Step 1: Find all logs linked to the record via junction object
        List<Trigger_Log_Link__c> links = [
            SELECT Trigger_Execution_Log__c
            FROM Trigger_Log_Link__c
            WHERE Related_Record_Id__c = :recordId
        ];

        system.debug('\n\n\n---- Found ' + links.size()+' links\n\n');
        system.debug(links);
   
        Set<Id> logIds = new Set<Id>();
        for (Trigger_Log_Link__c link : links) {
            logIds.add(link.Trigger_Execution_Log__c);
        }

        if (logIds.isEmpty()) return new List<Trigger_Execution_Log__c>();

        DateTime minTime = timeStamp.addSeconds(-2);
        DateTime maxTime = timeStamp.addSeconds(2);
        // Step 2: Fetch log records
        return [
            SELECT Id, Message__c, Timestamp__c, Context__c, SObject_Type__c, Trigger_Name__c, User__c, CreatedDate
            FROM Trigger_Execution_Log__c
            WHERE Id IN :logIds  OR (
                Context__c = 'before_insert' AND 
                SObject_Type__c = :sObjectType AND 
                Timestamp__c >= :minTime AND Timestamp__c <= :maxTime
            )
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=false)
    public static boolean getIsLoggingEnabled(){
        Trigger_Settings__c settings = Trigger_Settings__c.getOrgDefaults();
        boolean isLoggingEnabled = settings != null && settings.Enable_Logging__c;
        return isLoggingEnabled;
    }
}