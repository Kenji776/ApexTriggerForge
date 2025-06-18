public class AccountTriggerHelper_Sample {
    public static Map<Id, Integer> getContactCountsByAccount(List<Id> accountIds) {
        Map<Id, Integer> contactCounts = new Map<Id, Integer>();

        //It would be nice if we could dynamically get the function name, but alas reflecting is Apex is limited and while there are hacks
        //involving stack trace string extraction the performance trade off is probably not worth it.
        TriggerLogicController.log('getContactCountsByAccount',TriggerLogicController.LogLevel.F_START); //logs this action as the beginning of the function adding the '[START] tag for the log viewer'

        if(accountIds == null || accountIds.isEmpty()){
            TriggerLogicController.log('No accounts provided for calculation. Returning.',TriggerLogicController.LogLevel.ERROR);
            return contactCounts;
        }
        
        List<AggregateResult> results = [
            SELECT AccountId, COUNT(Id) contactCount
            FROM Contact
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ];

        TriggerLogicController.log('got aggregate result data for ' + results.size() + ' account records');

        for (AggregateResult ar : results) {
            Id accountId = (Id) ar.get('AccountId');
            Integer count = (Integer) ar.get('contactCount');
            contactCounts.put(accountId, count);
        }

        for (Id acctId : accountIds) {
            if (!contactCounts.containsKey(acctId)) {
                contactCounts.put(acctId, 0);
            }
        }

        TriggerLogicController.log(contactCounts);
        
        TriggerLogicController.log('getContactCountsByAccount',TriggerLogicController.LogLevel.F_END); //logs this action as the end of the function adding the '[END] tag for the log viewer'

        return contactCounts;
    }
    
    /**
     * Wrapper for getContactCountsByAccount function to allow for asynchronous execution
     * @param accountIds a list of account ids to process
     */
    @future
    public static void getContactCountsByAccount_Async(list<id> accountIds){

        /**
        * Because when we call a function async/future we do not have the instance of the TriggerLogicController that was originally constructed available
        * since we are in a different execution context. So when handling async functions that we want logging enabled we must manually initialize the TriggerLogicController
        * again like so.
        **/
        TriggerLogicController.initialize(
            'Async_Operation',
            'Account',
            'getContactCountsByAccount_Async',
            accountIds
        );

        TriggerLogicController.log('getContactCountsByAccount_Async',TriggerLogicController.LogLevel.F_START);
        getContactCountsByAccount(accountIds);
        TriggerLogicController.log('getContactCountsByAccount_Async',TriggerLogicController.LogLevel.F_END);

        //again, we have to make sure to manually flush the logs at the end of async execution chain to write them.
        TriggerLogicController.flushLogs();
    }
}