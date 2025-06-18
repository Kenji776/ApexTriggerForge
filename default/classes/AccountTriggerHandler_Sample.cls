/**
 * @description
 * This is a sample class that shows how to use the TriggerHandler framework. It gives examples of how to setup your functions to be 
 * toggleable and use optional async.
 
 * @group Trigger Handlers
 */
public class AccountTriggerHandler_Sample implements TriggerHandler {
    //Set this is the name of the sObjects this handler is for.
    public static final string OBJECT_TYPE = 'Account';

    public static boolean CAN_USE_ASYNC = TriggerLogicController.canInvokeFutureMethod();
    
    /**
     * Executes logic before inserting Account records.
     *
     * @param newList List of SObject records from Trigger.new
     * @return list of inserted accounts
     */
    public list<Account> handleBeforeInsert(List<SObject> newList) {
        List<Account> records = (List<Account>)newList;
        return records;
    }

    /**
     * Executes logic before updating Account records.
     *
     * @param newList List of SObject records from Trigger.new
     * @param oldMap Map of SObject records from Trigger.oldMap
     * @return list of updated accounts
     */
    public list<Account> handleBeforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        List<Account> records = (List<Account>)newList;
        return records;
    }

    /**
     * Executes logic before deleting Account records.
     *
     * @param oldList List of SObject records from Trigger.old
     * @return list of deleted accounts
     */
    public list<Account> handleBeforeDelete(List<SObject> oldList) {
        List<Account> records = (List<Account>)oldList;
        return records;
    }

    /**
     * Executes logic after inserting Account records.
     *
     * @param newList List of inserted records from Trigger.new
     * @return list of inserted accounts
     */
    public list<Account> handleAfterInsert(List<SObject> newList) {
        List<Account> records = (List<Account>)newList;
        return records;
    }

    /**
     * Executes logic after updating Account records.
     *
     * @param newList List of updated records (Trigger.new)
     * @param oldMap Map of old records (Trigger.oldMap)
     * @return list of updated accounts
     */
    public list<Account> handleAfterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        List<Account> records = (List<Account>)newList;

        List<Id> accountIds = TriggerLogicController.extractIds(newList);

        if (TriggerLogicController.isLogicEnabled(OBJECT_TYPE, 'after_update', 'getContactCountsByAccount')) {

            //you don't have to use async/future methods if you don't have a need for this. This framework was designed working around
            //large data loads so using async was commonly done but certainly not required if you don't need it.
            if(CAN_USE_ASYNC) AccountTriggerHelper_Sample.getContactCountsByAccount_Async(accountIds);
            else  AccountTriggerHelper_Sample.getContactCountsByAccount(accountIds);
        }

        // more methods here, controlled by the TriggerLogicController.isLogicEnabled method.
        return records;
    }

    /**
     * Executes logic after deleting Account records.
     *
     * @param oldMap Map of deleted records (Trigger.oldMap)
     * @return list of deleted accounts
     */
    public list<Account> handleAfterDelete(Map<Id, SObject> oldMap) {
        List<Account> records = (List<Account>) oldMap.values();
        return records;
    }

    /**
     * Executes logic after undeleting Account records.
     *
     * @param newList List of undeleted records (Trigger.new)
     * @return list of undeleted accounts
     */
    public list<Account> handleAfterUndelete(List<SObject> newList) {
        List<Account> records = (List<Account>)newList;
        return records;
    }
}
