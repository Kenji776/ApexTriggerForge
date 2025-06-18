public class AccountTriggerHelper_Sample implements Callable {
    public Object call(String action, Map<String, Object> args) {
        switch on action {
            when 'getContactCountsByAccount' {
                return getContactCountsByAccount((List<Account>) args.get('records'));
            }
            when else {
                throw new TriggerLogicController.ExtensionMalformedCallException('Method not implemented');
            }
        }
    }


    public static Map<Id, Integer> getContactCountsByAccount(List<Account> accounts) {
        Map<Id, Integer> contactCounts = new Map<Id, Integer>();

        //It would be nice if we could dynamically get the function name, but alas reflecting is Apex is limited and while there are hacks
        //involving stack trace string extraction the performance trade off is probably not worth it.
        TriggerLogicController.log('getContactCountsByAccount',TriggerLogicController.LogLevel.F_START); //logs this action as the beginning of the function adding the '[START] tag for the log viewer'

        if(accounts == null || accounts.isEmpty()){
            TriggerLogicController.log('No accounts provided for calculation. Returning.',TriggerLogicController.LogLevel.ERROR);
            return contactCounts;
        }
        
        list<Id> accountIds = new list<Id>(TriggerLogicController.extractIds(accounts));

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
}