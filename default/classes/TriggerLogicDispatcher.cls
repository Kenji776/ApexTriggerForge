/**
 * @description
 * TriggerLogicDispatcher handles the dynamic dispatch of trigger logic execution based on 
 * metadata configurations defined in Trigger_Logic_Control__mdt. It supports both synchronous 
 * and asynchronous invocation of methods and ensures that any required fields are populated 
 * before logic execution.
 * 
 * The dispatcher works in coordination with TriggerLogicController to evaluate enablement 
 * flags, construct logging metadata, and manage execution context.
 * 
 * @author Kenji776
 */
public class TriggerLogicDispatcher {

    /**
     * Executes the logic defined by a Trigger_Logic_Control__mdt record.
     * Resolves the class and method names dynamically, optionally ensures required fields 
     * are present on the input records, and invokes logic either synchronously or asynchronously.
     *
     * @param logicName The API name of the Trigger_Logic_Control__mdt record
     * @param records The list of sObjects to process
     * @return Object returned from the invoked method, if synchronous. Null otherwise.
     */
    public static Object runLogic(String logicName, List<SObject> records) {
        TriggerLogicController.log('[DISPATCHER] Running Logic: ' + logicName + ' for ' + records.size() + ' records');

        // Fetch metadata configuration for the logic
        Trigger_Logic_Control__mdt logic = TriggerLogicController.getTriggerLogicByName(logicName);

        // Abort if logic is disabled (and override hasn't been set)
        if (!TriggerLogicController.isLogicEnabled(logicName)) {
            TriggerLogicController.log('Trigger Logic for ' + logic.Function_Class_Name__c + '.' + logic.Function_Name__c + ' is disabled', TriggerLogicController.LogLevel.WARNING);
            return null;
        }

        // Ensure required fields are populated unless it's a before_insert trigger
        if (logic.Trigger_Context__c != 'before_insert') {
            records = ensureFieldsPopulated(records, logic);
        }

        Boolean canUseAsync = TriggerLogicController.canInvokeFutureMethod();
        String className = logic.Function_Class_Name__c;
        String methodName = logic.Function_Name__c;

        // Validate that the class name is present
        if (String.isBlank(className)) {
            throw new IllegalArgumentException('Trigger_Handler_Class_Name__c must be populated in metadata for logic: ' + methodName);
        }

        if (logic.Use_Async__c && canUseAsync) {
            // Serialize and invoke asynchronously if allowed
            executeAsync(className, methodName, JSON.serialize(records));
        } else {
            // Synchronous invocation
            Callable instance = (Callable) Type.forName(className).newInstance();
            Object returnData = instance.call(methodName, new Map<String, Object>{ 'records' => records });
            return returnData;
        }

        return null; // Async case
    }

    /**
     * Executes the given method on a Callable class asynchronously.
     * Used when the logic metadata specifies Use_Async__c = true and future methods are permitted.
     *
     * @param className The class name implementing Callable
     * @param methodName The method to call via Callable.call()
     * @param sObjectJson A JSON-serialized list of sObjects
     */
    @future
    public static void executeAsync(String className, String methodName, String sObjectJson) {
        List<SObject> records = (List<SObject>) JSON.deserialize(sObjectJson, List<SObject>.class);
        String objectType = records[0].getSObjectType().getDescribe().getName();

        List<Id> objectIds = new List<Id>(TriggerLogicController.extractIds(records));

        // Initialize logging context
        TriggerLogicController.initialize(
            'Async Execute Of ' + className + '.' + methodName,
            objectType,
            methodName,
            objectIds
        );        

        try {
            Callable target = (Callable) Type.forName(className).newInstance();
            Map<String, Object> args = new Map<String, Object>{
                'records' => records
            };
            target.call(methodName, args);
        } catch (Exception e) {
            System.debug('[AsyncTriggerExecutor] Error in executeAsync: ' + e.getMessage());
            TriggerLogicController.log('FATAL ERROR in executeAsync\n' + 
                                       className + '.' + methodName + '\n' + 
                                       e.getStackTraceString() + '\n' +
                                       e.getMessage() + '\n' +
                                       String.valueOf(e.getLineNumber()), TriggerLogicController.LogLevel.ERROR);
        } finally {
            TriggerLogicController.flushLogs();
        }
    }

    /**
     * Ensures all required fields listed in the metadata are populated on the given records.
     * If fields are missing, it performs a query to rehydrate the records with necessary data.
     *
     * @param records List of sObjects to verify
     * @param logic The Trigger_Logic_Control__mdt record defining required fields
     * @return A new list of enriched sObjects if data is missing, otherwise original input list
     */
    public static List<SObject> ensureFieldsPopulated(List<SObject> records, Trigger_Logic_Control__mdt logic) {
        if (records == null || records.isEmpty() || logic == null || String.isBlank(logic.Required_Input_Fields__c)) {
            return records;
        }

        TriggerLogicController.log('Required fields are missing from incoming sObject list. Constructing query to get required field data from database', TriggerLogicController.LogLevel.WARNING);

        // Parse field list from metadata
        Set<String> requiredFields = new Set<String>();
        for (String field : logic.Required_Input_Fields__c.split(',')) {
            if (!String.isBlank(field)) requiredFields.add(field.trim());
        }

        if (requiredFields.isEmpty()) {
            return records;
        }

        SObject sample = records[0];
        String objectType = sample.getSObjectType().getDescribe().getName();
        Map<String, SObjectField> fieldMap = sample.getSObjectType().getDescribe().fields.getMap();

        // Check which fields are already populated
        Set<String> presentFields = new Set<String>();
        for (String field : requiredFields) {
            if (fieldMap.containsKey(field)) {
                try {
                    Object val = sample.get(field);
                    if (val != null) {
                        presentFields.add(field);
                    }
                } catch (Exception e) {
                    // Field access may fail (e.g., due to permissions), ignore
                }
            }
        }

        // If all fields are already populated, return input
        if (presentFields.containsAll(requiredFields)) {
            return records;
        }

        // Identify missing but valid fields
        Set<String> fieldsToQuery = new Set<String>();
        for (String field : requiredFields) {
            if (fieldMap.containsKey(field) && !presentFields.contains(field)) {
                fieldsToQuery.add(field);
            }
        }

        if (fieldsToQuery.isEmpty()) {
            return records;
        }

        // Collect IDs for querying
        List<Id> recordIds = new List<Id>();
        for (SObject sObj : records) {
            recordIds.add((Id)sObj.get('Id'));
        }

        // Construct SOQL query dynamically
        String soql = 'SELECT Id, ' + String.join(new List<String>(fieldsToQuery), ', ') +
                      ' FROM ' + objectType +
                      ' WHERE Id IN :recordIds';

        List<SObject> queriedRecords = Database.query(soql);

        return queriedRecords;
    }
}
