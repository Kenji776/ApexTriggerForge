/**
 * Controller class for dynamic Apex trigger execution based on custom metadata configurations.
 * 
 * <p>This class enables modular trigger logic using a centralized dispatch system and evaluates
 * whether specific logic blocks should run using metadata flags. It also handles optional debug
 * logging tied to a custom setting, allowing verbose output for troubleshooting or suppressed logs
 * during bulk loads.
 *
 * <p>Key features include:
 * <ul>
 *   <li>Trigger context tracking to avoid duplicate execution</li>
 *   <li>Custom metadata-driven logic block enablement</li>
 *   <li>Logging and persistent execution logs controlled by custom settings</li>
 *   <li>TriggerHandler interface dispatch for cleaner modular logic</li>
 * </ul>
 *
 * @group Trigger Framework
 */
public class TriggerLogicController {
    private static Boolean initialized = false;
    private static Boolean isLoggingEnabled = false;
    private static boolean usePlatformEventBasedLogging = false;
    private static Set<String> hasRunContexts = new Set<String>();
    private static Map<String, Trigger_Logic_Control__mdt> logicMap = new Map<String, Trigger_Logic_Control__mdt>();
    private static List<String> debugLines = new List<String>();
    private static String triggerContext;
    private static String sObjectType;
    private static String triggerName; 
    private static Set<Id> recordIds = new Set<Id>();
    // Optional override list per sObjectType + context
    public static Map<String, Set<String>> overrideLogicMap = new Map<String, Set<String>>();

    public enum LogLevel {
        INFO,
        WARNING,
        ERROR,
        SUCCESS,
        F_START,
        F_END
    }
    /**
     * Initializes trigger context metadata and determines whether debug logging is enabled
     * based on the {@code Trigger_Settings__c} custom setting.
     *
     * <p>Should be called early in trigger execution to set context variables for logging and tracking.
     *
     * @param context      The trigger context string.
     * @param sObjType     The SObject type being processed.
     * @param trigName     The name of the trigger (inferred or explicit).
     * @param recordIds    List of incoming sObject Ids that this log will apply to
     */
    public static void initialize(String context, String sObjType, String trigName, list<Id> recordIds) {
        if (initialized) return;

        triggerContext = context;
        sObjectType = sObjType;
        triggerName = trigName;
        initialized = true;
        registerRecords(recordIds);

        // Attempt to get User-specific custom setting first
        Trigger_Settings__c settings = Trigger_Settings__c.getInstance(UserInfo.getUserId());

        system.debug('\n\n\n--- Logging Initialized');
        system.debug(JSON.serializePretty(settings));

        // Fallback to org defaults if no user-specific setting exists
        if (settings == null) {
            system.debug('\n\n\n--- No User Level Logging Settings Found. Using Org Defaults');
            settings = Trigger_Settings__c.getOrgDefaults();
            system.debug(JSON.serializePretty(settings));
        }

        isLoggingEnabled = settings != null && settings.Enable_Logging__c;

        usePlatformEventBasedLogging = settings != null && settings.Use_Platform_Event_Based_Logging__c;

        log('TriggerLogicController initialized with: ' + sObjType + ' | ' + context);
    }

    /**
     * Preloads logic block names that are enabled for the given SObject type and trigger context,
     * based on custom metadata (`Trigger_Logic_Control__mdt`).
     *
     * @param sObjectType     The API name of the SObject (e.g., 'Vehicle_Transaction__c').
     * @param triggerContext  The trigger context string (e.g., 'before_insert').
     */
    public static void preload() {
        TriggerLogicController.log('TRIGGER_LOGIC: Preloading logic metadata for: ' + sObjectType + ' / ' + triggerContext);

        List<Trigger_Logic_Control__mdt> records = [
            SELECT Is_Enabled__c, Trigger_Handler_Class_Name__c, Use_Async__c, Function_Name__c, DeveloperName, Function_Class_Name__c
            FROM Trigger_Logic_Control__mdt
            WHERE SObject_Type__c = :sObjectType
            AND Trigger_Context__c = :triggerContext
            AND Is_Enabled__c = TRUE
        ];

        for (Trigger_Logic_Control__mdt rec : records) {
            logicMap.put(rec.DeveloperName, rec);
            log('TRIGGER_LOGIC: Loaded logic block: ' + rec.DeveloperName);
        }
    }
    
    public static Trigger_Logic_Control__mdt getTriggerLogicByName(string logicName){
        log('TRIGGER_LOGIC: LOOKING FOR logicName: ' + logicName + ' in KeySet: ' + logicMap.keySet());
        return (Trigger_Logic_Control__mdt) logicMap.get(logicName);
    }

    /**
     * Determines whether a logic block is enabled for the given sObject/context/logicName.
     * Uses override list if set, otherwise falls back to cached metadata.
     */
    public static Boolean isLogicEnabled(String logicName) {
        String fullKey = sObjectType + ':' + triggerContext;
        
        if (overrideLogicMap.containsKey(fullKey)) {
            Boolean enabled = overrideLogicMap.get(fullKey).contains(logicName);
            log('TRIGGER_LOGIC [OVERRIDE]: isLogicEnabled? ' + logicName + ' = ' + enabled);
            return enabled;
        }

        Boolean enabled = logicMap.containsKey(logicName) || Test.isRunningTest();
        log('TRIGGER_LOGIC: isLogicEnabled? ' + logicName + ' = ' + enabled);
        return enabled;
    }

    /**
     * Sets a manual override of enabled logic blocks for a given sObject + triggerContext.
     */
    public static void setOverrideLogic(String sObjectType, String triggerContext, Set<String> logicNames) {
        String key = sObjectType + ':' + triggerContext;
        overrideLogicMap.put(key, logicNames);
        TriggerLogicController.log('TRIGGER_LOGIC: Override logic set for ' + key + ': ' + logicNames);
    }

    /**
     * Clears the manual override for the given sObject/context key.
     */
    public static void clearOverrideLogic(String sObjectType, String triggerContext) {
        String key = sObjectType + ':' + triggerContext;
        overrideLogicMap.remove(key);
        TriggerLogicController.log('TRIGGER_LOGIC: Override logic cleared for ' + key);
    }

    // Optional: add global clearAllOverrides() for testing or batching
    public static void clearAllOverrideLogic() {
        overrideLogicMap.clear();
    }

    /**
     * Dispatches trigger logic to the appropriate handler method based on the current trigger context.
     * Uses the {@code TriggerHandler} interface to enforce structure and avoid trigger bloat.
     *
     * <p>This method ensures each context only executes once per transaction.
     * Also initializes logging metadata for potential debug output.
     *
     * @param handler   The implementing handler class.
     * @param context   The trigger context string (e.g., 'before_insert').
     * @param newList   The {@code Trigger.new} or {@code Trigger.old} list.
     * @param oldMap    The {@code Trigger.oldMap} (can be null for inserts).
     */
    public static list<sObject> dispatch(TriggerHandler handler, String context, List<SObject> newList, Map<Id, SObject> oldMap) {
        list<sObject> result = newList != null && !newList.isEmpty() ? newList : oldMap.values();
        String sObjType = newList.isEmpty() ? 'Unknown' : newList[0].getSObjectType().getDescribe().getName();
        if (hasRunContexts.contains(context)) {
            TriggerLogicController.log('TRIGGER_LOGIC: Skipping already-run context: ' + context + ' For sObjectType: ' + sObjType);
            return result;
        }

        hasRunContexts.add(context);

        // Derive metadata for logging
        
        Id sampleRecordId = !newList.isEmpty() ? newList[0].Id : (oldMap != null && !oldMap.isEmpty() ? oldMap.keySet().iterator().next() : null);

        // Trigger name will need to be passed manually (optional) or inferred from sObject
        String inferredTriggerName = sObjType + 'Trigger';

        List<Id> recordIds = new List<Id>();
        for(sObject thisRecord : newList){
            if(thisRecord.Id != null) recordIds.add(thisRecord.Id);
        }
        initialize(context, sObjType, inferredTriggerName, recordIds);

        preload();
        log('Dispatching context ' + context + ' for ' + sObjType);

        if (context == 'before_insert') {
            result = handler.handleBeforeInsert(newList);
        } else if (context == 'before_update') {
            result = handler.handleBeforeUpdate(newList, oldMap);
        } else if (context == 'before_delete') {
            result = handler.handleBeforeDelete(newList);
        } else if (context == 'after_insert') {
            handler.handleAfterInsert(newList);
        } else if (context == 'after_update') {
            handler.handleAfterUpdate(newList, oldMap);
        } else if (context == 'after_delete') {
            handler.handleAfterDelete(oldMap);
        } else if (context == 'after_undelete') {
            handler.handleAfterUndelete(newList);
        } else {
            log('Unknown context: ' + context);
        }
        return result;
    }

    /**
     * Determines whether an @future method can be safely called
     * in the current execution context.
     *
     * @return true if @future methods are allowed to be called, false otherwise.
     */
    public static Boolean canInvokeFutureMethod() {
        // Future methods cannot be called from:
        // - Another @future method
        // - A batch class's execute() method
        return !(System.isFuture()  || System.isBatch());
    }

    /**
     * Determines the trigger context string based on standard Trigger context booleans.
     *
     * @param isBefore   Whether {@code Trigger.isBefore} is true.
     * @param isAfter    Whether {@code Trigger.isAfter} is true.
     * @param isInsert   Whether {@code Trigger.isInsert} is true.
     * @param isUpdate   Whether {@code Trigger.isUpdate} is true.
     * @param isDelete   Whether {@code Trigger.isDelete} is true.
     * @param isUndelete Whether {@code Trigger.isUndelete} is true.
     * @return           A string such as 'before_insert' or 'after_update', or null if undetermined.
     */
    public static String getTriggerContext(Boolean isBefore, Boolean isAfter, Boolean isInsert, Boolean isUpdate, Boolean isDelete, Boolean isUndelete) {
        if (isBefore) {
            if (isInsert) return 'before_insert';
            if (isUpdate) return 'before_update';
            if (isDelete) return 'before_delete';
        } else if (isAfter) {
            if (isInsert) return 'after_insert';
            if (isUpdate) return 'after_update';
            if (isDelete) return 'after_delete';
            if (isUndelete) return 'after_undelete';
        }
        return null;
    }

    /**
     * Logs a string message to debug output and adds it to an internal buffer for persistence.
     * No-op if logging is disabled via custom setting.
     *
     * @param message The log message string to output and store.
     */
    public static void log(String message) {
        log(message, LogLevel.INFO);
    }
    public static void log(String message, LogLevel level) {
        if (level == null) level = LogLevel.INFO;

        String prefix = '';
        switch on level {
            when ERROR      { prefix = '[ERROR] '; }
            when WARNING    { prefix = '[WARNING] '; }
            when SUCCESS    { prefix = '[SUCCESS] '; }
            when F_START    { prefix = '[START] '; }
            when F_END      { prefix = '[END] '; }
            when INFO       { /* optional prefix */ }
    }

        String fullMessage = prefix + message;

        System.debug('\n');
        System.debug('>>>>> ' + fullMessage + '\n');

        if (!isLoggingEnabled && !Test.isRunningTest()) return;

        String timestamped = '[' + String.valueOf(Datetime.now()) + '] ' + fullMessage;
        debugLines.add(timestamped);
    }

    /**
     * Serializes an object to JSON (pretty format) and logs the result.
     * Useful for structured visibility of complex data in logs.
     * No-op if logging is disabled.
     *
     * @param obj The object to serialize and log.
     */
    public static void log(Object obj, LogLevel level) {
        try {
            String json = JSON.serializePretty(obj);
            log(json, level);
        } catch (Exception e) {
            log('Failed to serialize object: ' + e.getMessage(), LogLevel.ERROR);
            system.debug(obj);
        }
    }

    // Overload fallback for default INFO
    public static void log(Object obj) {
        log(obj, LogLevel.INFO);
    }

    /**
     * Writes the current session's debug log lines to a {@code Trigger_Execution_Log__c} record.
     * This provides persistent storage for debugging or auditing purposes.
     * Clears the internal buffer after writing. No-op if logging is disabled or no lines exist.
     */
    public static void flushLogs() {
        system.debug('\n\n\n----- Flush Logs Called');
        system.debug('isLoggingEnabled:' + isLoggingEnabled);
        system.debug('debugLines.isEmpty():' + debugLines.isEmpty());

        if ((!isLoggingEnabled || debugLines.isEmpty()) && !Test.isRunningTest()) return;

        log('Writing Log Data for ' + debugLines.size() + ' debug lines to ' + recordIds.size() + ' related records' );  


        if(!usePlatformEventBasedLogging){
            log('Writing logs using direct DML');
            Trigger_Execution_Log__c logRecord;
            try {
                logRecord = new Trigger_Execution_Log__c(
                    Message__c         = String.join(debugLines, '\n').left(32768),
                    Timestamp__c       = Datetime.now(),
                    Context__c         = triggerContext.left(200),
                    SObject_Type__c    = sObjectType.left(200),
                    Trigger_Name__c    = triggerName.left(200),
                    User__c            = UserInfo.getUserId()
                );
                insert logRecord;
            } catch (Exception e) {
                log('TRIGGER_LOGIC: Failed to persist main log: ' + e.getMessage());
                return;
            }

            try {
                if (!recordIds.isEmpty()) {
                    List<Trigger_Log_Link__c> links = new List<Trigger_Log_Link__c>();
                    for (Id recId : recordIds) {
                        links.add(new Trigger_Log_Link__c(
                            Trigger_Execution_Log__c = logRecord.Id,
                            Related_Record_Id__c = recId
                        ));
                    }
                    insert links;
                }
            } catch (Exception e) {
                log('TRIGGER_LOGIC: Failed to insert link records: ' + e.getMessage());
            }
        }else{
            log('Writing logs using Platform Events');
            Trigger_Log__e logEvent = new Trigger_Log__e(
                Message__c         = String.join(debugLines, '\n').left(32768),
                Timestamp__c       = Datetime.now(),
                Context__c         = triggerContext.left(200),
                SObject_Type__c    = sObjectType.left(200),
                Trigger_Name__c    = triggerName.left(200),
                User__c            = UserInfo.getUserId(),
                Related_Record_Ids__c = String.join(new set<Id>(recordIds), ',')
            );
            EventBus.publish(logEvent);
        }

        debugLines.clear();
        recordIds.clear();
        initialized = false;
    }

    

    public static void registerRecords(List<Id> recIds) {
        recIds = recIds != null ? recIds : new list<Id>();
        recordIds = new Set<Id>(recIds);
    }

    /**
     * Extracts and returns the set of unique, non-null IDs from a list of sObjects,
     * based on a specified field name.
     * 
     * This is useful when working with multiple sObject types and needing to dynamically
     * extract a related lookup or reference field's ID.
     * 
     * @param records A list of sObject records to scan.
     * @param fieldName The name of the field to extract IDs from (e.g., 'Invoice__c').
     * @return A List of unique, non-null IDs found in the given field across the records.
     */
    public static Set<Id> extractIds(List<sObject> records) {
        Set<Id> result = new Set<Id>();

        for (sObject rec : records) {
            Object value = rec.get('Id');
            if (value != null && value instanceof Id) {
                result.add((Id)value);
            }
        }

        return result;
    }

    public class ExtensionMalformedCallException extends Exception {}

}