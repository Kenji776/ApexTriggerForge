public class RecordReprocessorController {
    @AuraEnabled(cacheable=true)
    public static List<Trigger_Logic_Control__mdt> getEnabledLogicOptions(String sObjectType, String triggerContext) {

        system.debug('\n\n\n----- Running logic options fetch for sObjectType: ' + sObjectType + ' and triggerContext: ' + triggerContext + '\n\n');
        // Step 1: Create a new list of logic options')
        return [
            SELECT Is_Enabled__c,Trigger_Context__c, Description__c, DeveloperName, Required_Input_Fields__c, Trigger_Handler_Class_Name__c, Id   
            FROM Trigger_Logic_Control__mdt 
            WHERE SObject_Type__c = :sObjectType
              AND Trigger_Context__c = :triggerContext
        ];
    }

    @AuraEnabled
    public static Id launchProcessingJob(String sObjectType, String triggerContext, List<Id> logicMetadataIds, String whereClause, List<String> fields, Integer batchSize) {
        try {
            if (batchSize == null) batchSize = 200;

            Map<String, String> dedupedFields = new Map<String, String>();
            for (String f : fields) {
                dedupedFields.put(f.toLowerCase(), f);
            }
            dedupedFields.put('id', 'Id');
            fields = new List<String>(dedupedFields.values());

            // Query logic metadata records
            List<Trigger_Logic_Control__mdt> logicRecords = [
                SELECT DeveloperName, Trigger_Handler_Class_Name__c
                FROM Trigger_Logic_Control__mdt
                WHERE Id IN :logicMetadataIds
            ];

            RecordReprocessorBatchJob batch = new RecordReprocessorBatchJob(
                sObjectType,
                triggerContext,
                fields,
                logicRecords,
                whereClause
            );

            return Database.executeBatch(batch, batchSize);

        } catch (Exception e) {
            System.debug('[ERROR] Exception during launchProcessingJob: ' + e.getMessage());
            throw new AuraHandledException('Unable to launch batch job: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableSObjectTypes() {
        Set<String> types = new Set<String>();
        for (Trigger_Logic_Control__mdt rec : [
            SELECT SObject_Type__c 
            FROM Trigger_Logic_Control__mdt
            WHERE SObject_Type__c != null
            ORDER By SObject_Type__c
        ]) {
            types.add(rec.SObject_Type__c);
        }

        List<Map<String, String>> options = new List<Map<String, String>>();
        for (String sObj : types) {
            options.add(new Map<String, String>{ 'label' => sObj, 'value' => sObj });
        }
        return options;
    }

    @AuraEnabled
    public static List<SObject> runPreviewQuery(String sObjectType, String whereClause) {
        if (String.isBlank(sObjectType)) {
            throw new AuraHandledException('SObject type is required.');
        }

        String baseQuery = 'SELECT Id, Name, CreatedDate FROM ' + sObjectType;
        if (!String.isBlank(whereClause)) {
            baseQuery += ' WHERE ' + whereClause;
        }
        baseQuery += ' LIMIT 100';

        try {
            return Database.query(baseQuery);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid SOQL: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static integer getNumRecords(String sObjectType, String whereClause){
        String baseQuery = 'SELECT Count() FROM ' + sObjectType;
        if (!String.isBlank(whereClause)) {
            baseQuery += ' WHERE ' + whereClause;
        }
        try {            
            return Database.countQuery(baseQuery); 
        } catch (Exception e) {
            throw new AuraHandledException('Invalid SOQL: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getDescribeFields(String sObjectType) {
        if (String.isBlank(sObjectType)) {
            throw new AuraHandledException('SObject type is required.');
        }

        try {
            // Get the describe result for the sObject
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(sObjectType);
            if (objType == null) {
                throw new AuraHandledException('Invalid SObject type: ' + sObjectType);
            }

            Schema.DescribeSObjectResult describeResult = objType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            List<String> fieldNames = new List<String>(fieldMap.keySet());
            fieldNames.sort(); // Optional: sort alphabetically

            return fieldNames;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to describe fields: ' + e.getMessage());
        }
    }


    @AuraEnabled(cacheable=false)
    public static ApexJobStatusWrapper checkApexJobStatus(Id jobId) {
        AsyncApexJob job = [
            SELECT Id, Status, CompletedDate, NumberOfErrors, TotalJobItems, JobItemsProcessed, ApexClassId, ExtendedStatus
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        Integer percentComplete = 0;
        if (job.TotalJobItems > 0) {
            percentComplete = (job.JobItemsProcessed * 100) / job.TotalJobItems;
        }
        if ((job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted')) {
            percentComplete = 100;
        }

        // Smart Auto-Abort Logic: If a batch failed and job is still running, abort it
        if (job.NumberOfErrors > 0) {
            System.abortJob(jobId); // 🔥 Kill it immediately
            job = [
                    SELECT Id, Status, CompletedDate, NumberOfErrors, TotalJobItems, JobItemsProcessed, ApexClassId, ExtendedStatus
                    FROM AsyncApexJob
                    WHERE Id = :jobId
                    LIMIT 1
            ];
            System.debug('[ABORTED] Job had errors and was force-aborted');
        }

        return new ApexJobStatusWrapper(job.Status, percentComplete, job.NumberOfErrors, job.TotalJobItems, job.JobItemsProcessed, job.ExtendedStatus);
    }

    public class ApexJobStatusWrapper {
        @AuraEnabled public String Status;
        @AuraEnabled public Integer PercentComplete;
        @AuraEnabled public Integer NumberOfErrors;
        @AuraEnabled public Integer TotalJobItems;
        @AuraEnabled public Integer JobItemsProcessed;
        @AuraEnabled public String ExtendedStatus;

        public ApexJobStatusWrapper(String status, Integer percentComplete, Integer NumberOfErrors, Integer TotalJobItems, Integer JobItemsProcessed, String ExtendedStatus) {
            this.Status = status;
            this.PercentComplete = percentComplete;
            this.NumberOfErrors = NumberOfErrors;
            this.TotalJobItems = TotalJobItems;
            this.JobItemsProcessed = JobItemsProcessed;
            this.ExtendedStatus = ExtendedStatus;
        }
    }
}