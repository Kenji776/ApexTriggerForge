trigger TriggerLogTrigger on Trigger_Log__e  (after insert) {
    List<Trigger_Execution_Log__c> logs = new List<Trigger_Execution_Log__c>();
    Map<String, List<String>> eventIdToRelatedIds = new Map<String, List<String>>();

    try{
        // Step 1: Prepare log records and track related IDs
        for (Trigger_Log__e evt : Trigger.new) {
            logs.add(new Trigger_Execution_Log__c(
                Message__c      = evt.Message__c,
                Timestamp__c    = evt.Timestamp__c,
                Context__c      = evt.Context__c,
                SObject_Type__c = evt.SObject_Type__c,
                Trigger_Name__c = evt.Trigger_Name__c,
                User__c         = evt.User__c
            ));

            if (!String.isBlank(evt.Related_Record_Ids__c)) {
                List<String> ids = evt.Related_Record_Ids__c.split(',');
                eventIdToRelatedIds.put(evt.ReplayId, ids);
            }
        }

        // Step 2: Insert logs and map them to the original events by index
        insert logs;

        List<Trigger_Log_Link__c> links = new List<Trigger_Log_Link__c>();
        for (Integer i = 0; i < logs.size(); i++) {
            Trigger_Execution_Log__c logRecord = logs[i];
            Trigger_Log__e evt = Trigger.new[i];

            if (eventIdToRelatedIds.containsKey(evt.ReplayId)) {
                for (String recId : eventIdToRelatedIds.get(evt.ReplayId)) {
                    links.add(new Trigger_Log_Link__c(
                        Trigger_Execution_Log__c = logRecord.Id,
                        Related_Record_Id__c     = recId.trim()
                    ));
                }
            }
        }

        if (!links.isEmpty()) {
            insert links;
        }
    }catch(exception e){
        Trigger_Execution_Log__c failLog = new Trigger_Execution_Log__c(
                Message__c      = e.getMessage() + '\n\nStack Trace:\n' + e.getStackTraceString(),
                Timestamp__c    = dateTime.now(),
                Context__c      = 'Platform Event Subscriber',
                User__c         = UserInfo.getUserId(),
                SObject_Type__c = 'Trigger_Execution_Log__c',
                Trigger_Name__c = 'after_insert'
        );
        insert failLog;
    }
}