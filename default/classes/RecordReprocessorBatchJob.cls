/**
 * A batch Apex class used to reprocess records by invoking trigger logic
 * as if the records were being inserted, updated, or deleted.
 * 
 * This class dynamically loads the appropriate TriggerHandler implementation based
 * on the target SObject and applies specific trigger logic in a batch-safe manner.
 * 
 * Implements Database.Batchable<SObject> for batch execution,
 * and Database.Stateful to maintain state across batch executions if needed.
 */
global class RecordReprocessorBatchJob implements Database.Batchable<SObject>, Database.Stateful {

    private final List<Trigger_Logic_Control__mdt> logicMetadata;

    private final String sObjectType;        // API name of the SObject type to process
    private final String whereClause;        // WHERE clause to filter records
    private final Set<String> logicToRun;    // Set of logic steps to run (e.g., 'before_update', etc.)
    private final List<String> fieldsToQuery;// Fields to query from the SObject
    private final String triggerContext;     // Trigger context to simulate (e.g., 'before_update')

    /**
     * Constructor to initialize the batch job with context and filtering logic.
     *
     * @param sObjectType     API name of the SObject (e.g., 'Account', 'CustomObject__c')
     * @param triggerContext  Trigger context to simulate (e.g., 'before_update')
     * @param fieldsToQuery   Fields to query from the SObject
     * @param logicMetadata   Set of Trigger_Logic_Control__mdt record containing logic definitions to run
     * @param whereClause     Optional WHERE clause to filter SObject records
     */
    public RecordReprocessorBatchJob(
        String sObjectType,
        String triggerContext,
        List<String> fieldsToQuery,
        List<Trigger_Logic_Control__mdt> logicMetadata,
        String whereClause
    ) {
        this.sObjectType = sObjectType;
        this.triggerContext = triggerContext;
        this.fieldsToQuery = fieldsToQuery;
        this.logicMetadata = logicMetadata;
        this.whereClause = whereClause;
    }

    /**
     * Builds the dynamic SOQL query to select records for processing.
     *
     * @param bc  Batchable context object
     * @return QueryLocator to retrieve records in batches
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT ' + String.join(fieldsToQuery, ', ') + ' FROM ' + sObjectType;
        if (!String.isBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }
        return Database.getQueryLocator(query);
    }

    /**
     * Executes logic on each batch of records.
     *
     * @param bc     Batchable context object
     * @param scope  List of SObjects in the current batch
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        for (Trigger_Logic_Control__mdt logic : logicMetadata) {

            List<Id> recordIds = new list<Id>(TriggerLogicController.extractIds(scope));

            TriggerLogicController.initialize(
                'Reprocess Of ' + logic.DeveloperName,
                scope[0].getSObjectType().getDescribe().getName(),
                logic.DeveloperName,
                recordIds
            );

            system.debug('\n\n\n----- Trigger Logic Controller Initialized for record ids...');
            system.debug(recordIds);

            String handlerClassName = logic.Trigger_Handler_Class_Name__c;
            Type handlerType;

            try {
                if (String.isNotBlank(handlerClassName)) {
                    handlerType = Type.forName(handlerClassName);
                    if (handlerType == null) {
                        throw new TriggerLogicException('Specified handler class not found: ' + handlerClassName);
                    }
                } else {
                    // Attempt to auto-deduce if not provided
                    handlerType = getTriggerHandlerInstance(sObjectType);
                }

                Object instance = handlerType.newInstance();
                if (!(instance instanceof TriggerHandler)) {
                    throw new TriggerLogicException('Class does not implement TriggerHandler: ' + handlerType.getName());
                }

                TriggerHandler handler = (TriggerHandler) instance;

                // Set and run logic override
                TriggerLogicController.setOverrideLogic(sObjectType, triggerContext, new Set<String>{ logic.DeveloperName });

                List<SObject> updatedRecords = TriggerLogicController.dispatch(handler, triggerContext, scope, null);

                if (
                    new List<String>{ 'before_insert', 'before_update', 'before_delete' }.contains(triggerContext)
                    && updatedRecords != null && !updatedRecords.isEmpty()
                ) {
                    update updatedRecords;
                }

            } catch (Exception ex) {
                System.debug('[ERROR] Failed processing logic: ' + logic.DeveloperName + ' - ' + ex.getMessage());
                throw new TriggerLogicException('Error in logic "' + logic.DeveloperName + '": ' + ex.getMessage());
            } finally {
                TriggerLogicController.flushLogs();
                TriggerLogicController.clearOverrideLogic(sObjectType, triggerContext);
            }
        }
    }

    /**
     * Finish method for any final steps after batch completes.
     * Currently unused but available for logging or post-processing.
     *
     * @param bc Batchable context object
     */
    public void finish(Database.BatchableContext bc) {
        // Intentionally left blank; implement if post-batch logic is needed.
    }

    /**
     * Dynamically resolves and validates the TriggerHandler class for the SObject.
     *
     * @param sObjectApiName The API name of the SObject (e.g., 'CustomObject__c')
     * @return Type handle to the corresponding TriggerHandler class
     * @throws TriggerLogicException if class is missing or invalid
     */
    public static Type getTriggerHandlerInstance(String sObjectApiName) {
        if (String.isBlank(sObjectApiName)) {
            throw new TriggerLogicException('SObject API name cannot be blank.');
        }

        // Strip '__c' and underscores to derive the handler class name
        String baseName = sObjectApiName.replaceAll('__c$', '').replaceAll('_', '');
        String className = baseName + 'TriggerHandler';

        Type handlerType = Type.forName(className);
        if (handlerType == null) {
            throw new TriggerLogicException('Trigger handler class not found: ' + className);
        }

        // Ensure the resolved class implements the TriggerHandler interface
        Object instance = handlerType.newInstance();
        if (!(instance instanceof TriggerHandler)) {
            throw new TriggerLogicException('Class ' + className + ' does not implement TriggerHandler.');
        }

        return handlerType;
    }

    /**
     * Custom exception class for trigger logic errors.
     */
    public class TriggerLogicException extends Exception {}
}
