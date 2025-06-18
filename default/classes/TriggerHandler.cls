/**
 * TriggerHandler interface for trigger framework.
 * @group Trigger Framework
 */

public interface TriggerHandler {
    list<sObject> handleBeforeInsert(List<SObject> newList);
    list<sObject> handleBeforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap);
    list<sObject> handleBeforeDelete(List<SObject> oldList);
    list<sObject> handleAfterInsert(List<SObject> newList);
    list<sObject> handleAfterUpdate(List<SObject> newList, Map<Id, SObject> oldMap);
    list<sObject> handleAfterDelete(Map<Id, SObject> oldMap);
    list<sObject> handleAfterUndelete(List<SObject> newList);
}