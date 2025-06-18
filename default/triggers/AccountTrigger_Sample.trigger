/**
 * @description
 * Trigger for Account object, delegates execution to the
 * AccountTriggerHandler_Sample class using TriggerLogicController.
 *
 * This setup enables dynamic logic control via custom metadata (Trigger_Logic_Control__mdt),
 * ensures each trigger context runs only once per transaction,
 * and allows for clean, bulk-safe logic delegation.
 *
 * Supported Contexts:
 * - before insert, update, delete
 * - after insert, update, delete, undelete
 *
 * @group Trigger Entry Points
 */
trigger AccountTrigger_Sample on Account  (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    AccountTriggerHandler_Sample handler = new AccountTriggerHandler_Sample();

    // Determine trigger context string
    String context = TriggerLogicController.getTriggerContext(
        Trigger.isBefore,
        Trigger.isAfter,
        Trigger.isInsert,
        Trigger.isUpdate,
        Trigger.isDelete,
        Trigger.isUndelete
    );

   

    // Dispatch if context is valid
    if (!String.isBlank(context)) {
        try{
            TriggerLogicController.dispatch(
                handler,
                context,
                Trigger.isDelete ? Trigger.old : Trigger.new,
                Trigger.oldMap
            );
        }catch(exception e){
            TriggerLogicController.log('FATAL ERROR in AccountTriggerHandler_Sample Trigger\n'+ 
                                        context+'\n'+ 
                                        e.getStackTraceString()+'\n'+
                                        e.getMessage()+'\n'+
                                        String.valueOf(e.getLineNumber()), TriggerLogicController.LogLevel.ERROR);
        }
        TriggerLogicController.flushLogs();
    }
}