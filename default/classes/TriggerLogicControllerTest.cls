/**
 * @description
 * Unit tests for the TriggerLogicController class
 *
 * @group Unit Tests
 * @author Slalom Consulting
 */
@isTest
private class TriggerLogicControllerTest {


    @isTest
    static void testPreloadAndLogicChecks() {


        Test.startTest();

        // Preload logic from mock metadata
        TriggerLogicController.preload('Test_Object__c', 'before_insert');

        // Should now return true
        System.assertEquals(true, TriggerLogicController.isLogicEnabled('Test_Object__c', 'before_insert', 'MockLogic'));

        Test.stopTest();
    }

    @isTest
    static void testLoggingAndFlushing() {
        Test.startTest();

        // Simulate initializing a context
        TriggerLogicController.initialize(
            'after_insert',
            'Test_Object__c',
            'TestTrigger',
            null
        );

        // Log string
        TriggerLogicController.log('Test message');

        // Log object
        TriggerLogicController.log(new Map<String, String>{ 'key' => 'value' });

        // Flush logs to Trigger_Execution_Log__c
        TriggerLogicController.flushLogs();

        List<Trigger_Execution_Log__c> logs = [
            SELECT Id, Message__c, SObject_Type__c, Context__c
            FROM Trigger_Execution_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assert(logs[0].Message__c.contains('Test message'));
        System.assertEquals('Test_Object__c', logs[0].SObject_Type__c);
        System.assertEquals('after_insert', logs[0].Context__c);

        Test.stopTest();
    }

    @isTest
    static void testMultipleInitializeIsIdempotent() {
        TriggerLogicController.initialize('before_update', 'Test_Object__c', 'MyTrigger', new list<Id>{'001000000000000AAA'});
        TriggerLogicController.initialize('after_delete', 'Test_Object__c', 'AnotherTrigger', new list<Id>{'001000000000001BBB'});
        TriggerLogicController.log('Should still reflect first init context');
        TriggerLogicController.flushLogs();

        Trigger_Execution_Log__c log = [SELECT Context__c, Trigger_Name__c, SObject_Type__c FROM Trigger_Execution_Log__c LIMIT 1];
        System.assertEquals('before_update', log.Context__c);
        System.assertEquals('MyTrigger', log.Trigger_Name__c);
    }

    @isTest
    static void testFlushWithoutLogsDoesNothing() {
        Test.startTest();
        TriggerLogicController.flushLogs(); // should do nothing / not error
        Test.stopTest();
    }
}
